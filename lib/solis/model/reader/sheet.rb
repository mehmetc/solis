require_relative 'sheet/simple_sheets'
require 'data_collector/config_file'
require 'linkeddata'
require_relative 'shacl'

module Solis
  class Model
    class Reader
      class Sheet
        def self.read(key, spreadsheet_id, options = {})
          class << self
            def spreadsheet_id_from_url(sheet_url)
              tmp = URI(sheet_url).path.split('/')
              tmp[tmp.index('d') + 1]
            end
            def parse_entity_data(entity_name, graph_prefix, _graph_name, e, options = {})
              properties = {}
              entity_data = e
              if entity_data && !entity_data.nil? && (entity_data.count > 0)
                entity_data.each do |p|
                  property_name = I18n.transliterate(p['name'].strip)
                  min_max = {}

                  %w[min max].each do |n|
                    min_max[n] = if p.key?(n) && p[n] =~ /\d+/
                                   p[n].to_i.to_s
                                 else
                                   ''
                                 end
                  end
                  puts "#{entity_name}.#{property_name}"
                  unless p.key?('name')
                    puts "No 'name' property found"
                    pp p
                  end

                  if properties.key?(property_name)
                    puts "Found #{entity_name}.#{property_name}"
                  else
                    datatype_prefix, datatype_name = p['datatype'].split(':')
                    properties[property_name] = {
                      datatype: p['datatype'],
                      path: "#{graph_prefix}:#{property_name.to_s.classify}",
                      cardinality: { min: min_max['min'], max: min_max['max'] },
                      same_as: p['sameas'],
                      description: p['description']
                    }
                  end
                end
              end

              properties
            rescue => e
              raise Solis::Error::General, e.message
            end
            def header(data)
              out = data[:ontologies][:all].map do |k, v|
                "@prefix #{k}: <#{v[:uri]}> ."
              end.join("\n")

              "#{out}\n"
            end
            def extract_metadata(sheets)
              ontology_metadata = {}
              sheets['_METADATA'].each { |e| ontology_metadata.store(e['key'].to_sym, e['value']) }
              ontology_metadata
            rescue => e
              raise Solis::Error::General, e.message
            end

            def extract_prefixes(sheets)
              prefixes = {}
              sheets['_PREFIXES'].each do |e|
                prefixes.store(e['prefix'].to_sym, { uri: e['uri'], base: e['base'].eql?('*') })
              end
              prefixes
            rescue => e
              raise Solis::Error::General, e.message
            end
          end

          DataCollector::ConfigFile.path = options[:config_path] if options[:config_path]
          DataCollector::ConfigFile.name = options[:config_name] if options[:config_name]
          cache_dir = DataCollector::ConfigFile.include?(:cache) ? DataCollector::ConfigFile[:cache] : '/tmp'

          if ::File.exist?("#{cache_dir}/#{spreadsheet_id}.json") && (options.include?(:from_cache) && options[:from_cache])
            Solis.logger.info("from cache #{cache_dir}/#{spreadsheet_id}.json")
            data = JSON.parse(::File.read("#{cache_dir}/#{spreadsheet_id}.json"), { symbolize_names: true })
            return data
          else
            sheets = sheet_from_id(key, spreadsheet_id)

            validate(sheets)
            if sheets.is_a?(Hash)
              raise "No _REFERENCES sheet found" unless sheets.key?("_REFERENCES")
              # read other ontologies
              Solis.logger.info('Reading referenced ontologies')
              references = sheets['_REFERENCES'].map do |reference|
                { sheet_url: reference['sheeturl'], description: reference['description'] }
              end

              cache_dir = DataCollector::ConfigFile.include?(:cache) ? DataCollector::ConfigFile[:cache] : '/tmp'
              ::File.open("#{::File.absolute_path(cache_dir)}/#{spreadsheet_id}.json", 'wb') do |f|
                f.puts references.to_json
              end
            else
              references = sheets
            end

            datas = []
            references.each do |v|
              sheet_id = spreadsheet_id_from_url(v[:sheet_url])

              sheet_data = sheet_from_id(key, sheet_id)
              if sheet_data.key?("_PREFIXES")
                datas << parse(sheet_data, follow: true)
                sleep 30
              else
                datas << sheet_data
              end
            end

            raw_shacl = StringIO.new(to_shacl(datas))
            # raw_shacl = to_shacl(datas)
            # return Shacl.read(raw_shacl)
            DataCollector::Input.new.from_uri(raw_shacl, content_type: 'text/turtle', raw: true)
          end
        rescue => e
          raise Solis::Error::General, e.message
        end

        private

        def self.sheet_from_id(key, spreadsheet_id)
          Solis.logger.info("from source #{spreadsheet_id}")
          session = SimpleSheets.new(key, spreadsheet_id)
          session.key = key
          sheets = {}
          session.worksheets.each do |worksheet|
            sheet = ::Sheet.new(worksheet)
            sheets[sheet.title] = sheet
          end
          sheets
        end

        def self.to_shacl(datas)
          shacl_prefix = datas.first[:ontologies][:all].select { |_, v| v[:uri] =~ /shacl/ }.keys.first
          shacl_prefix = 'sh' if shacl_prefix.nil?

          out = header(datas.first)

          datas.each do |data|
            data[:entities].each do |entity_name, metadata|
              graph_prefix = data[:ontologies][:base][:prefix]
              graph_name = data[:ontologies][:base][:uri]

              description = metadata[:comment]
              label = metadata[:label]
              target_class = "#{graph_prefix}:#{entity_name}"
              node = metadata[:sub_class_of]

              if node && !node.empty?
                node = node.first if node.is_a?(Array)
                node = node.strip
                node += 'Shape' if node != /Shape$/ # && node =~ /^#{graph_prefix}:/
              else
                node = target_class
              end

              out += %(
#{graph_prefix}:#{entity_name}Shape
    a               #{shacl_prefix}:NodeShape ;
    #{shacl_prefix}:description "#{description&.gsub('"', "'")&.gsub(/\n|\r/, '')}" ;
    #{shacl_prefix}:targetClass  #{target_class} ;#{
                unless node.nil? || node.empty?
                  "\n    #{shacl_prefix}:node         #{node} ;"
                end}
                #{shacl_prefix}:name         "#{label}" ;
)
              metadata[:properties].each do |property, property_metadata|
                attribute = property.to_s.strip
                next if attribute.empty?

                description = property_metadata[:description]&.gsub('"', "'")&.gsub(/\n|\r/, '').strip
                path = "#{graph_prefix}:#{attribute}"
                datatype = property_metadata[:datatype].strip
                min_count = property_metadata[:cardinality][:min].strip
                max_count = property_metadata[:cardinality][:max].strip

                if datatype =~ /^#{graph_prefix}:/ || datatype =~ /^<#{graph_name}/
                  out += %(    #{shacl_prefix}:property [#{shacl_prefix}:path #{path} ;
                 #{shacl_prefix}:name "#{attribute}" ;
                 #{shacl_prefix}:description "#{description}" ;
                 #{shacl_prefix}:nodeKind #{shacl_prefix}:IRI ;
                 #{shacl_prefix}:class    #{datatype} ;#{min_count =~ /\d+/ ? "\n                 #{shacl_prefix}:minCount #{min_count} ;" : ''}#{max_count =~ /\d+/ ? "\n                 #{shacl_prefix}:maxCount #{max_count} ;" : ''}
    ] ;
)
                else
                  if datatype.eql?('rdf:langString')
                    out += %(    #{shacl_prefix}:property [#{shacl_prefix}:path #{path} ;
                 #{shacl_prefix}:name "#{attribute}";
                 #{shacl_prefix}:description "#{description}" ;
                 #{shacl_prefix}:uniqueLang true ;
                 #{shacl_prefix}:datatype #{datatype} ;#{min_count =~ /\d+/ ? "\n                 #{shacl_prefix}:minCount #{min_count} ;" : ''}
    ] ;
)
                  else
                    out += %(    #{shacl_prefix}:property [#{shacl_prefix}:path #{path} ;
                 #{shacl_prefix}:name "#{attribute}";
                 #{shacl_prefix}:description "#{description}" ;
                 #{shacl_prefix}:datatype #{datatype} ;#{min_count =~ /\d+/ ? "\n                 #{shacl_prefix}:minCount #{min_count} ;" : ''}#{max_count =~ /\d+/ ? "\n                 #{shacl_prefix}:maxCount #{max_count} ;" : ''}
    ] ;
)
                  end

                end
              end
              out += ".\n"
            end
          end
          out
        rescue StandardError => e
          puts e.message
        end

        def self.validate(sheets)
          prefixes = sheets['_PREFIXES']
          metadata = sheets['_METADATA']

          raise "_PREFIXES tab must have ['base', 'prefix', 'uri'] as a header at row 1" unless (%w[base prefix uri] - prefixes.header).length == 0
          raise '_PREFIXES.base can only have one base URI' if prefixes.map { |m| m['base'] }.grep(/\*/).count != 1

          raise "_METADATA tab must have ['key', 'value'] as a header at row 1" unless (%w[key value] - metadata.header).length == 0

          if sheets.key?('_ENTITIES')
            entities = sheets['_ENTITIES']
            raise "_ENTITIES tab must have ['name', 'nameplural', 'description', 'subclassof', 'sameas'] as a header at row 1" unless (%w[name nameplural description subclassof sameas] - entities.header).length == 0

            entities.each do |entity|
              raise "Plural not found for #{entity['name']}" if entity['nameplural'].nil? || entity['nameplural'].empty?
            end
          else
            raise "Missing _ENTITIES tab" unless sheets.key?('_REFERENCES')
          end

          if sheets.key?('_REFERENCES')
            references = sheets['_REFERENCES']
            raise "_REFERENCES tab must have ['sheeturl', 'description', 'entityrange'] as a header at row 1" unless (%w[sheeturl description entityrange] - references.header).length == 0
          else
            raise "Missing _REFERENCES tab" unless sheets.key?('_ENTITIES')
          end
        rescue => e
          raise Solis::Error::General, e.message
        end

        def self.parse(sheets, options = {})
          validate(sheets)

          prefixes = extract_prefixes(sheets)
          ontology_metadata = extract_metadata(sheets)
          entities = {}

          base_uri = prefixes.select { |_k, v| v[:base] }.select { |s| !s.empty? }

          graph_prefix = base_uri.keys.first
          graph_name = base_uri.values.first[:uri]
          sheets['_ENTITIES'].each do |e|

            top_class = e['name'].to_s
            top_sheet = sheets[top_class] || nil
            entity_data = parse_entity_data(e['name'].to_s, graph_prefix, graph_name, top_sheet, { prefixes: prefixes, follow: options[:follow] })

            if entity_data.empty?
              entity_data[:id] = {
                datatype: 'xsd:string',
                path: "#{graph_prefix}:id",
                cardinality: { min: '1', max: '1' },
                same_as: '',
                description: 'systeem UUID'
              }
            end

            entities.store(e['name'].to_sym, { description: e['description'],
                                               plural: e['nameplural'],
                                               label: e['name'].to_s.strip,
                                               sub_class_of: e['subclassof'].nil? || e['subclassof'].empty? ? [] : [e['subclassof']],
                                               same_as: e['sameas'],
                                               properties: entity_data })
          end

          data = {
            entities: entities,
            ontologies: {
              all: prefixes,
              base: {
                prefix: graph_prefix,
                uri: graph_name
              }
            },
            metadata: ontology_metadata
          }
        rescue => e
          raise Solis::Error::General, e.message
        end


      end
    end
  end
end