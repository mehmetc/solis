require_relative 'sheet/simple_sheets'
require 'data_collector/config_file'
require 'linkeddata'
require_relative 'shacl'

module Solis
  class Model
    class Reader
      class Sheet
        class << self
          def read(key, spreadsheet_id, options = {})
            setup_config(options)

            if use_cache?(spreadsheet_id, options)
              return read_from_cache(spreadsheet_id)
            else
              sheet = fetch_sheet(key, spreadsheet_id)
              validate(sheet)

              if sheet.is_a?(Hash)
                references = extract_references(sheet, spreadsheet_id)
              else
                references = sheet
              end

              datas = process_references(key, references)
              raw_shacl = StringIO.new(to_shacl(datas))

              DataCollector::Input.new.from_uri(raw_shacl, content_type: 'text/turtle', raw: true)
            end
          rescue => e
            raise Solis::Error::General, e.message
          end

          private

          def setup_config(options)
            DataCollector::ConfigFile.path = options[:config_path] if options[:config_path]
            DataCollector::ConfigFile.name = options[:config_name] if options[:config_name]
          end

          def cache_dir
            DataCollector::ConfigFile.include?(:cache) ? DataCollector::ConfigFile[:cache] : '/tmp'
          end

          def use_cache?(spreadsheet_id, options)
            cache_file = "#{cache_dir}/#{spreadsheet_id}.json"
            ::File.exist?(cache_file) && options[:from_cache]
          end

          def read_from_cache(spreadsheet_id)
            cache_file = "#{cache_dir}/#{spreadsheet_id}.json"
            Solis.logger.info("from cache #{cache_file}")
            JSON.parse(::File.read(cache_file), { symbolize_names: true })
          end

          def fetch_sheet(key, spreadsheet_id)
            Solis.logger.info("from source #{spreadsheet_id}")
            session = SimpleSheets.new(key, spreadsheet_id)
            session.key = key

            sheets = {}
            session.worksheets.each do |worksheet|
              sheet = ::Sheet.new(worksheet)
              sheets[sheet.title] = sheet
            end
            sheets
          rescue => e
            if e.message =~ /code = 400/
              raise Solis::Error::NotAllowed, 'Google Auth key is invalid/missing.'
            elsif e.message =~ /code = 403/
              raise Solis::Error::NotAllowed, 'Google Sheet not shared.'
            end
          end

          def extract_references(sheets, spreadsheet_id)
            raise "No _REFERENCES sheet found" unless sheets.key?("_REFERENCES")

            Solis.logger.info('Reading referenced ontologies')
            references = sheets['_REFERENCES'].map do |reference|
              { sheet_url: reference['sheeturl'], description: reference['description'] }
            end

            save_references_to_cache(references, spreadsheet_id)
            references
          end

          def save_references_to_cache(references, spreadsheet_id)
            cache_path = ::File.absolute_path(cache_dir)
            ::File.open("#{cache_path}/#{spreadsheet_id}.json", 'wb') do |f|
              f.puts references.to_json
            end
          end

          def process_references(key, references)
            datas = []
            references.each do |ref|
              sheet_id = spreadsheet_id_from_url(ref[:sheet_url])
              sheet_data = fetch_sheet(key, sheet_id)

              if sheet_data.key?("_PREFIXES")
                datas << parse(sheet_data, follow: true)
                sleep 30 # Consider making this configurable or removing if unnecessary
              else
                datas << sheet_data
              end
            end
            datas
          end

          def spreadsheet_id_from_url(sheet_url)
            tmp = URI(sheet_url).path.split('/')
            tmp[tmp.index('d') + 1]
          end

          def validate(sheets)
            validate_prefixes(sheets['_PREFIXES'])
            validate_metadata(sheets['_METADATA'])
            validate_entities_or_references(sheets)
          end

          def validate_prefixes(prefixes)
            unless (%w[base prefix uri] - prefixes.header).empty?
              raise "_PREFIXES tab must have ['base', 'prefix', 'uri'] as a header at row 1"
            end

            if prefixes.map { |m| m['base'] }.grep(/\*/).count != 1
              raise '_PREFIXES.base can only have one base URI'
            end
          end

          def validate_metadata(metadata)
            unless (%w[key value] - metadata.header).empty?
              raise "_METADATA tab must have ['key', 'value'] as a header at row 1"
            end
          end

          def validate_entities_or_references(sheets)
            if sheets.key?('_ENTITIES')
              validate_entities(sheets['_ENTITIES'])
            else
              raise "Missing _ENTITIES tab" unless sheets.key?('_REFERENCES')
            end

            if sheets.key?('_REFERENCES')
              validate_references(sheets['_REFERENCES'])
            else
              raise "Missing _REFERENCES tab" unless sheets.key?('_ENTITIES')
            end
          end

          def validate_entities(entities)
            required_headers = %w[name nameplural description subclassof sameas]
            unless (required_headers - entities.header).empty?
              raise "_ENTITIES tab must have #{required_headers} as a header at row 1"
            end

            entities.each do |entity|
              if entity['nameplural'].nil? || entity['nameplural'].empty?
                raise "Plural not found for #{entity['name']}"
              end
            end
          end

          def validate_references(references)
            required_headers = %w[sheeturl description entityrange]
            unless (required_headers - references.header).empty?
              raise "_REFERENCES tab must have #{required_headers} as a header at row 1"
            end
          end

          def parse(sheets, options = {})
            validate(sheets)

            prefixes = extract_prefixes(sheets)
            ontology_metadata = extract_metadata(sheets)
            entities = build_entities(sheets, prefixes, options)

            {
              entities: entities,
              ontologies: {
                all: prefixes,
                base: {
                  prefix: prefixes.find { |_k, v| v[:base] }.first,
                  uri: prefixes.find { |_k, v| v[:base] }.last[:uri]
                }
              },
              metadata: ontology_metadata
            }
          end

          def build_entities(sheets, prefixes, options)
            entities = {}
            graph_prefix = prefixes.find { |_k, v| v[:base] }.first
            graph_name = prefixes.find { |_k, v| v[:base] }.last[:uri]

            sheets['_ENTITIES'].each do |e|
              entity_name = e['name'].to_s
              entity_sheet = sheets[entity_name]

              entity_data = parse_entity_data(
                entity_name,
                graph_prefix,
                graph_name,
                entity_sheet,
                { prefixes: prefixes, follow: options[:follow] }
              )

              # Add default ID property if no properties exist
              if entity_data.empty?
                entity_data[:id] = default_id_property(graph_prefix)
              end

              entities[entity_name.to_sym] = {
                description: e['description'],
                plural: e['nameplural'],
                label: entity_name.strip,
                sub_class_of: e['subclassof'].nil? || e['subclassof'].empty? ? [] : [e['subclassof']],
                same_as: e['sameas'],
                properties: entity_data
              }
            end

            entities
          end

          def default_id_property(graph_prefix)
            {
              datatype: 'xsd:string',
              path: "#{graph_prefix}:id",
              cardinality: { min: '1', max: '1' },
              same_as: '',
              description: 'systeem UUID'
            }
          end

          def parse_entity_data(entity_name, graph_prefix, _graph_name, entity_data, options = {})
            return {} if entity_data.nil? || entity_data.count <= 0

            properties = {}

            entity_data.each do |p|
              property_name = I18n.transliterate(p['name'].strip)
              min_max = extract_min_max(p)

              puts "#{entity_name}.#{property_name}"
              validate_property(p, entity_name, property_name)
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

            properties
          end

          def extract_min_max(property)
            {}.tap do |min_max|
              %w[min max].each do |n|
                min_max[n] = if property.key?(n) && property[n] =~ /\d+/
                               property[n].to_i.to_s
                             else
                               ''
                             end
              end
            end
          end

          def validate_property(property, entity_name, property_name)
            unless property.key?('name')
              puts "No 'name' property found"
            end
          end

          def extract_metadata(sheets)
            ontology_metadata = {}
            sheets['_METADATA'].each { |e| ontology_metadata[e['key'].to_sym] = e['value'] }
            ontology_metadata
          end

          def extract_prefixes(sheets)
            prefixes = {}
            sheets['_PREFIXES'].each do |e|
              prefixes[e['prefix'].to_sym] = { uri: e['uri'], base: e['base'].eql?('*') }
            end
            prefixes
          end

          def header(data)
            prefixes = data[:ontologies][:all].map do |k, v|
              "@prefix #{k}: <#{v[:uri]}> ."
            end.join("\n")

            "#{prefixes}\n"
          end

          def to_shacl(datas)
            shacl_prefix = determine_shacl_prefix(datas.first)
            output = header(datas.first)

            datas.each do |data|
              data[:entities].each do |entity_name, metadata|
                output += generate_entity_shape(entity_name, metadata, data, shacl_prefix)
              end
            end

            output
          rescue StandardError => e
            puts e.message
            raise
          end

          def determine_shacl_prefix(data)
            prefix = data[:ontologies][:all].find { |_, v| v[:uri] =~ /shacl/ }&.first
            prefix || 'sh'
          end

          def generate_entity_shape(entity_name, metadata, data, shacl_prefix)
            graph_prefix = data[:ontologies][:base][:prefix]
            graph_name = data[:ontologies][:base][:uri]

            shape = <<~SHAPE
              
              #{graph_prefix}:#{entity_name}Shape
                  a               #{shacl_prefix}:NodeShape ;
                  #{shacl_prefix}:description "#{escape_string(metadata[:description])}" ;
                  #{shacl_prefix}:targetClass  #{graph_prefix}:#{entity_name} ;
            SHAPE

            node = determine_node(metadata[:sub_class_of], graph_prefix, entity_name)
            shape += "    #{shacl_prefix}:node         #{node} ;\n" if node
            shape += "    #{shacl_prefix}:name         \"#{metadata[:label]}\" ;\n"

            metadata[:properties].each do |property, property_metadata|
              shape += generate_property_shape(
                property,
                property_metadata,
                graph_prefix,
                graph_name,
                shacl_prefix
              )
            end

            shape += ".\n"
          end

          def determine_node(sub_class_of, graph_prefix, entity_name)
            if sub_class_of && !sub_class_of.empty?
              node = sub_class_of.is_a?(Array) ? sub_class_of.first : sub_class_of
              node = node.strip
              node += 'Shape' unless node =~ /Shape$/
              node
            else
              "#{graph_prefix}:#{entity_name}"
            end
          end

          def generate_property_shape(property, metadata, graph_prefix, graph_name, shacl_prefix)
            attribute = property.to_s.strip
            return "" if attribute.empty?

            description = escape_string(metadata[:description])
            path = "#{graph_prefix}:#{attribute}"
            datatype = metadata[:datatype].strip
            min_count = metadata[:cardinality][:min].strip
            max_count = metadata[:cardinality][:max].strip

            if datatype =~ /^#{graph_prefix}:/ || datatype =~ /^<#{graph_name}/
              generate_object_property(
                path, attribute, description, datatype,
                min_count, max_count, shacl_prefix
              )
            elsif datatype.eql?('rdf:langString')
              generate_language_string_property(
                path, attribute, description,
                datatype, min_count, shacl_prefix
              )
            else
              generate_datatype_property(
                path, attribute, description, datatype,
                min_count, max_count, shacl_prefix
              )
            end
          end

          def generate_object_property(path, attribute, description, datatype, min_count, max_count, sh)
            property = <<~PROPERTY
                #{sh}:property [#{sh}:path #{path} ;
                     #{sh}:name "#{attribute}" ;
                     #{sh}:description "#{description}" ;
                     #{sh}:nodeKind #{sh}:IRI ;
                     #{sh}:class    #{datatype} ;
            PROPERTY

            property += "                 #{sh}:minCount #{min_count} ;\n" if min_count =~ /\d+/
            property += "                 #{sh}:maxCount #{max_count} ;\n" if max_count =~ /\d+/
            property += "    ] ;\n"
          end

          def generate_language_string_property(path, attribute, description, datatype, min_count, sh)
            property = <<~PROPERTY
                #{sh}:property [#{sh}:path #{path} ;
                     #{sh}:name "#{attribute}";
                     #{sh}:description "#{description}" ;
                     #{sh}:uniqueLang true ;
                     #{sh}:datatype #{datatype} ;
            PROPERTY

            property += "                 #{sh}:minCount #{min_count} ;\n" if min_count =~ /\d+/
            property += "    ] ;\n"
          end

          def generate_datatype_property(path, attribute, description, datatype, min_count, max_count, sh)
            property = <<~PROPERTY
                #{sh}:property [#{sh}:path #{path} ;
                     #{sh}:name "#{attribute}";
                     #{sh}:description "#{description}" ;
                     #{sh}:datatype #{datatype} ;
            PROPERTY

            property += "                 #{sh}:minCount #{min_count} ;\n" if min_count =~ /\d+/
            property += "                 #{sh}:maxCount #{max_count} ;\n" if max_count =~ /\d+/
            property += "    ] ;\n"
          end

          def escape_string(str)
            return "" unless str
            str.gsub('"', "'").gsub(/\n|\r/, '')
          end
        end
      end
    end
  end
end