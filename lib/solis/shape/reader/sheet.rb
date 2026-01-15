require_relative 'simple_sheets'
require 'active_support/all'
require 'active_support/hash_with_indifferent_access'
require 'rdf/vocab'
require 'solis/error'

module Solis
  module Shape
    module Reader
      class Sheet
        def self.read(key, spreadsheet_id, options = {})
          class << self
            def progress(i, data)
              if data.key?(:job_id) && data.key?(:store)
                job_id = data[:job_id]
                progress = data[:store]
                progress[job_id] = i
              end
            end

            def validate(sheets, prefixes = nil, metadata = nil)
              # raise "Please make sure the sheet contains '_PREFIXES', '_METADATA', '_ENTITIES' tabs" unless (%w[_PREFIXES _METADATA _ENTITIES] - sheets.keys).length == 0

              prefixes = sheets.key?('_PREFIXES') && prefixes.nil? ? sheets['_PREFIXES'] : prefixes
              metadata = sheets.key?('_METADATA') && metadata.nil? ? sheets['_METADATA'] : metadata

              raise "_PREFIXES tab must have ['base', 'prefix', 'uri'] as a header at row 1" unless (%w[base prefix uri] - prefixes.header).length == 0
              raise '_PREFIXES.base can only have one base URI' if prefixes.map { |m| m['base'] }.grep(/\*/).count != 1

              raise "_METADATA tab must have ['key', 'value'] as a header at row 1" unless (%w[key value] - metadata.header).length == 0

              if sheets.key?('_ENTITIES')
                entities = sheets['_ENTITIES']
                raise "_ENTITIES tab must have ['name', 'nameplural', 'description', 'subclassof', 'sameas'] as a header at row 1" unless (%w[name nameplural description subclassof sameas] - entities.header).length == 0

                entities.each do |entity|
                  raise "Plural not found for #{entity['name']}" if entity['nameplural'].nil? || entity['nameplural'].empty?
                end
              end

              if sheets.key?('_REFERENCES')
                references = sheets['_REFERENCES']
                raise "_REFERENCES tab must have ['sheeturl', 'description', 'entityrange'] as a header at row 1" unless (%w[sheeturl description entityrange] - references.header).length == 0
              end

              sheets.each do |sheet_name, sheet|
                if sheet_name !~ /^_/
                  entities = sheets[sheet_name]
                  raise "#{sheet_name} tab must have ['Name', 'Description', 'MIN', 'MAX', 'sameAs', 'datatype'] as a header at row 1" unless (%w[name description min max sameas datatype] - entities.header).length == 0
                end
              end
            end

            def read_sheets(key, spreadsheet_id, options)
              data = nil
              prefixes = options[:prefixes] || nil
              metadata = options[:metadata] || nil

              cache_dir = ConfigFile.include?(:cache) ? ConfigFile[:cache] : '/tmp'

              if ::File.exist?("#{cache_dir}/#{spreadsheet_id}.json") && (options.include?(:from_cache) && options[:from_cache])
                Solis::LOGGER.info("from cache #{cache_dir}/#{spreadsheet_id}.json")
                data = JSON.parse(::File.read("#{cache_dir}/#{spreadsheet_id}.json"), { symbolize_names: true })
                return data
              else
                Solis::LOGGER.info("from source #{spreadsheet_id}")
                session = SimpleSheets.new(key, spreadsheet_id)
                session.key = key
                sheets = {}
                session.worksheets.each do |worksheet|
                  sheet = ::Sheet.new(worksheet)
                  sheets[sheet.title] = sheet
                end

                validate(sheets, prefixes, metadata)
              end
              sheets
            end

            def process_sheet(key, sheet_id, sheets, options = { follow: true })
              entities = {}
              prefixes = {}
              ontology_metadata = {}

              sheets['_PREFIXES'].each do |e|
                prefixes.store(e['prefix'].to_sym, { uri: e['uri'], base: e['base'].eql?('*') })
              end
              sheets['_METADATA'].each { |e| ontology_metadata.store(e['key'].to_sym, e['value']) }

              base_uri = prefixes.select { |_k, v| v[:base] }.select { |s| !s.empty? }

              graph_prefix = base_uri.keys.first
              graph_name = base_uri.values.first[:uri]

              sheets['_ENTITIES'].each do |e|

                top_class = e['name'].to_s
                top_sheet = sheets[top_class] || nil
                # if sheets[top_class].nil? && !(e['subclassof'].nil? || e['subclassof'].empty?)
                #   top_sheet = sheets[e['subclassof'].split(':').last.to_s] || nil
                # end
                # if prefixes[graph_prefix][:data].nil? || prefixes[graph_prefix][:data].empty?
                entity_data = parse_entity_data(e['name'].to_s, graph_prefix, graph_name, top_sheet, { key: key, prefixes: prefixes, follow: options[:follow] })
                #  prefixes[graph_prefix][:data] = entity_data
                # else
                #  entity_data = prefixes[graph_prefix][:data]
                # end

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
                                                   order: e['order'],
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

              cache_dir = ConfigFile.include?(:cache) ? ConfigFile[:cache] : '/tmp'
              # ::File.open("#{::File.absolute_path(cache_dir)}/#{spreadsheet_id}.json", 'wb') do |f|
              ::File.open("#{::File.absolute_path(cache_dir)}/#{sheet_id}.json", 'wb') do |f|
                f.puts data.to_json
              end

              data
            rescue StandardError => e
              raise Solis::Error::GeneralError, e.message
            end

            def parse_entity_data(entity_name, graph_prefix, _graph_name, e, options = {})
              properties = {}
              entity_data = e
              if entity_data && !entity_data.nil? && (entity_data.count > 0)
                entity_data.each do |p|
                  property_name = I18n.transliterate(p['name'].strip)
                  next if property_name.empty?
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
                      order: p['order'],
                      description: p['description']
                    }

                    # unless graph_prefix.eql?(datatype_prefix.to_sym)
                    #   prefixes = options[:prefixes]
                    #   if prefixes.key?(datatype_prefix.to_sym) && !prefixes[datatype_prefix.to_sym][:sheet_url].empty?
                    #     tmp = URI(prefixes[datatype_prefix.to_sym][:sheet_url]).path.split('/')
                    #     spreadsheet_id = tmp[tmp.index('d') + 1]
                    #
                    #     processed_remote_sheet = {}
                    #     if prefixes[datatype_prefix.to_sym].key?(:data) && !prefixes[datatype_prefix.to_sym][:data].empty?
                    #       processed_remote_sheet = prefixes[datatype_prefix.to_sym][:data]
                    #     else
                    #       if options[:follow]
                    #         sleep 30
                    #         remote_sheet = read_sheets(options[:key], spreadsheet_id, { from_cache: true })
                    #         processed_remote_sheet = process_sheet(options[:key], remote_sheet, {follow: false})
                    #         prefixes[datatype_prefix.to_sym][:data] = processed_remote_sheet
                    #       end
                    #     end
                    #
                    #     processed_remote_sheet
                    #   end
                    # end

                  end
                end
              end

              properties
            end

            def build_plantuml(datas)
              #              !pragma layout elk
              out = %(@startuml
skinparam classFontSize 14
!define LIGHTORANGE
skinparam groupInheritance 1
skinparam componentStyle uml2
skinparam wrapMessageWidth 100
skinparam ArrowColor #Maroon

title #{datas.first[:metadata][:title]} - #{datas.first[:metadata][:version]} - #{Time.now}
              )

              out += "\npackage #{datas.first[:ontologies][:base][:prefix]} {\n"
              datas.each do |data|
                data[:entities].each do |entity_name, metadata|
                  out += "\nclass #{entity_name}"

                  properties = metadata[:properties]
                  relations = []
                  unless properties.nil? || properties.empty?
                    out += "{\n"
                    properties.each do |property, property_metadata|
                      out += "\t{field} #{property_metadata[:datatype]} : #{property} \n"

                      if property_metadata[:datatype].split(':').first.eql?(data[:ontologies][:base][:prefix].to_s)
                        relations << "#{property_metadata[:datatype].split(':').last} - #{property_metadata[:cardinality].key?(:max) && !property_metadata[:cardinality][:max].empty? ? "\"#{property_metadata[:cardinality][:max]}\"" : ''} #{entity_name} : #{property} >"
                      end
                    end
                    out += "}\n"
                    out += relations.join("\n")
                  end

                  out += "\n"
                  sub_classes = metadata[:sub_class_of]
                  sub_classes = [sub_classes] unless sub_classes.is_a?(Array)
                  sub_classes.each do |sub_class|
                    out += "#{entity_name} --|> #{sub_class.split(':').last}\n" unless sub_class.empty?
                  end
                end
              end
              out += %(
hide circle
hide methods
hide empty members
@enduml
          )

              out
            rescue StandardError => e
              puts e.message
            end

            def datatype_lookup(datatype, as = :sql)
              datatypes = {
                'xsd:string' => { sql: 'text' },
                'xsd:date' => { sql: 'date' },
                'xsd:boolean' => { sql: 'bool' },
                'xsd:integer' => { sql: 'integer' }
              }

              datatypes.default = { sql: 'text' }

              datatypes[datatype][as]
            end

            def build_shacl(datas)
              shacl_prefix = datas.first[:ontologies][:all].select { |_, v| v[:uri] =~ /shacl/ }.keys.first
              shacl_prefix = 'sh' if shacl_prefix.nil?

              out = header(datas.first)

              datas.each do |data|
                data[:entities].each do |entity_name, metadata|
                  graph_prefix = data[:ontologies][:base][:prefix]
                  graph_name = data[:ontologies][:base][:uri]

                  description = metadata[:description]
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
                    order = property_metadata.key?(:order) && property_metadata[:order] ? property_metadata[:order]&.strip : nil

                    if datatype =~ /^#{graph_prefix}:/ || datatype =~ /^<#{graph_name}/
                      out += %(    #{shacl_prefix}:property [#{shacl_prefix}:path #{path} ;
                 #{shacl_prefix}:name "#{attribute}" ;
                 #{shacl_prefix}:description "#{description}" ;#{order.nil? ? '' : "\n                 #{shacl_prefix}:order #{order} ;"}
                 #{shacl_prefix}:nodeKind #{shacl_prefix}:IRI ;
                 #{shacl_prefix}:class    #{datatype} ;#{min_count =~ /\d+/ ? "\n                 #{shacl_prefix}:minCount #{min_count} ;" : ''}#{max_count =~ /\d+/ ? "\n                 #{shacl_prefix}:maxCount #{max_count} ;" : ''}
    ] ;
)
                    else
                      if datatype.eql?('rdf:langString') && max_count.eql?('1')
                        out += %(    #{shacl_prefix}:property [#{shacl_prefix}:path #{path} ;
                 #{shacl_prefix}:name "#{attribute}";
                 #{shacl_prefix}:description "#{description}" ;#{order.nil? ? '' : "\n                 #{shacl_prefix}:order #{order} ;"}
                 #{shacl_prefix}:uniqueLang true ;
                 #{shacl_prefix}:datatype #{datatype} ;#{min_count =~ /\d+/ ? "\n                 #{shacl_prefix}:minCount #{min_count} ;" : ''}
    ] ;
)
                      elsif datatype.eql?('rdf:langString')
                        out += %(    #{shacl_prefix}:property [#{shacl_prefix}:path #{path} ;
                 #{shacl_prefix}:name "#{attribute}";
                 #{shacl_prefix}:description "#{description}" ;#{order.nil? ? '' : "\n                 #{shacl_prefix}:order #{order} ;"}
                 #{shacl_prefix}:datatype #{datatype} ;#{min_count =~ /\d+/ ? "\n                 #{shacl_prefix}:minCount #{min_count} ;" : ''}#{max_count =~ /\d+/ ? "\n                 #{shacl_prefix}:maxCount #{max_count} ;" : ''}
    ] ;
)
                      else
                        out += %(    #{shacl_prefix}:property [#{shacl_prefix}:path #{path} ;
                 #{shacl_prefix}:name "#{attribute}";
                 #{shacl_prefix}:description "#{description}" ;#{order.nil? ? '' : "\n                 #{shacl_prefix}:order #{order} ;"}
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

            def build_schema(datas)
              classes = {}
              datatype_properties = {}
              object_properties = {}

              format = :ttl
              graph_prefix = datas.first[:ontologies][:base][:prefix]
              graph_name = datas.first[:ontologies][:base][:uri]

              all_prefixes = {}
              datas.first[:ontologies][:all].each { |k, v| all_prefixes[k] = v[:uri] }

              datas.each do |data|
                data[:entities].each do |entity_name, metadata|
                  classes[entity_name] = {
                    comment: metadata[:description],
                    label: entity_name.to_s,
                    type: 'owl:Class',
                    subClassOf: metadata[:sub_class_of]
                  }

                  metadata[:properties].each do |property, property_metadata|
                    attribute = property.to_s.strip
                    description = property_metadata[:description]
                    path = "#{graph_name}#{attribute}"
                    datatype = property_metadata[:datatype]

                    schema_data = datatype_properties[attribute] || {}
                    domain = schema_data[:domain] || []
                    domain << "#{graph_name}#{entity_name}"
                    datatype_properties[attribute] = {
                      domain: domain,
                      comment: description,
                      label: attribute.to_s,
                      range: datatype,
                      type: 'rdf:Property'
                    }
                    unless property_metadata[:same_as].nil? || property_metadata[:same_as].empty?
                      datatype_properties[attribute]['owl:sameAs'] =
                        property_metadata[:same_as]
                    end

                    subclass_data = data[:entities][entity_name][:sub_class_of] || []
                    unless property_metadata[:cardinality][:min].empty?
                      subclass_data << RDF::Vocabulary.term(type: 'owl:Restriction',
                                                            onProperty: path,
                                                            minCardinality: property_metadata[:cardinality][:min])
                    end
                    unless property_metadata[:cardinality][:max].empty?
                      subclass_data << RDF::Vocabulary.term(type: 'owl:Restriction',
                                                            onProperty: path,
                                                            maxCardinality: property_metadata[:cardinality][:max])
                    end
                    data[:entities][entity_name][:sub_class_of] = subclass_data
                  end
                end
              end

              lp = RDF::StrictVocabulary(graph_name)
              o = ::Class.new(lp) do
                ontology(graph_name.to_sym, {
                  "dc11:title": datas.first[:metadata][:title].freeze,
                  "dc11:description": datas.first[:metadata][:description].freeze,
                  "dc11:date": Time.now.to_s.freeze,
                  "dc11:creator": datas.first[:metadata][:author].freeze,
                  "owl:versionInfo": datas.first[:metadata][:version].freeze,
                  type: 'owl:Ontology'.freeze
                })

                classes.each do |k, v|
                  term k.to_sym, v
                end
                object_properties.each do |k, v|
                  property k.is_a?(RDF::URI) ? k.value.to_sym : k.to_sym, v
                end

                datatype_properties.each do |k, v|
                  property k.is_a?(RDF::URI) ? k.value.to_sym : k.to_sym, v
                end
              end

              RDF::Vocabulary.register(graph_prefix.to_sym, o, uri: graph_name)

              graph = RDF::Graph.new
              graph.graph_name = RDF::URI(graph_name)

              datas.each do |data|
                data[:entities].select { |_k, v| !v[:same_as].empty? }.each do |k, v|
                  same_as_value = v[:same_as].strip

                  if same_as_value.start_with?('<') && same_as_value.end_with?('>')
                    # Full URI format: <http://xmlns.com/foaf/0.1/Person>
                    uri_string = same_as_value[1...-1]
                    rdf_verb = RDF::URI(uri_string)
                  else
                    # Prefixed name format: foaf:Person
                    prefix, verb = same_as_value.split(':')
                    rdf_vocabulary = RDF::Vocabulary.from_sym(prefix.upcase)
                    rdf_verb = rdf_vocabulary[verb.to_sym]
                  end

                  graph << RDF::Statement.new(rdf_verb, RDF::RDFV.type, RDF::OWL.Class)
                  graph << RDF::Statement.new(rdf_verb, RDF::Vocab::OWL.sameAs, o[k.to_sym])
                rescue StandardError => e
                  puts e.message
                end
              end

              graph << o.to_enum

              graph.dump(format, prefixes: all_prefixes)
            rescue StandardError => e
              puts e.message
            end

            def build_inflections(datas)
              inflections = {}
              datas.each do |data|
                data[:entities].each do |entity, metadata|
                  inflections[entity] = metadata[:plural]
                  inflections[entity.to_s.underscore.to_sym] = metadata[:plural].underscore
                end
              end

              inflections.to_json
            rescue StandardError => e
              puts e.message
            end

            def build_json_schema(shacl_file)
              def map_rdf_datatype_to_json_schema(datatype)
                # NOTE: "format" not supported by every client.
                case datatype
                when /string$/
                  { "type" => "string" }
                when /integer$/
                  { "type" => "integer" }
                when /decimal$/, /double$/, /float$/
                  { "type" => "number" }
                when /boolean$/
                  { "type" => "boolean" }
                when /date$/, /dateTime$/
                  { "type" => "string", "format" => "date-time" }
                when /anyURI$/
                  { "type" => "string", "format" => "uri" }
                when /datatypes\/edtf/, /edtf$/i
                  { "type" => "string", "format" => "edtf" }
                else
                  { "type" => "string" }
                end
              end

              def self.default_value_for_type(type)
                case type
                when "string"
                  ""
                when "integer", "number"
                  0
                when "boolean"
                  false
                when "array"
                  []
                when "object"
                  {}
                else
                  ""
                end
              end

              graph = RDF::Graph.new
              graph.from_ttl(shacl_file)

              #graph = RDF::Graph.load(StringIO.new(shacl_file), format: :ttl, content_type: "text/turtle")
              json_schema = {
                "$schema" => "http://json-schema.org/draft-07/schema#",
                "type" => "object",
                "properties" => {},
                "required" => []
              }

              graph.query([nil, RDF.type, RDF::Vocab::SHACL.NodeShape]) do |shape|
                shape_subject = shape.subject

                graph.query([shape_subject, RDF::Vocab::SHACL.property, nil]) do |prop_stmt|
                  prop_subject = prop_stmt.object
                  prop_name = graph.query([prop_subject, RDF::Vocab::SHACL.path, nil]).first&.object.to_s
                  datatype = map_rdf_datatype_to_json_schema(graph.query([prop_subject, RDF::Vocab::SHACL.datatype, nil]).first&.object)
                  min_count = graph.query([prop_subject, RDF::Vocab::SHACL.minCount, nil]).first&.object&.to_i
                  max_count = graph.query([prop_subject, RDF::Vocab::SHACL.maxCount, nil]).first&.object&.to_i
                  pattern = graph.query([prop_subject, RDF::Vocab::SHACL.pattern, nil]).first&.object&.to_s

                  json_schema["properties"][prop_name] = {}
                  json_schema["properties"][prop_name]["type"] = datatype["type"] if datatype
                  json_schema["properties"][prop_name]["pattern"] = pattern if pattern

                  json_schema["required"] << prop_name if min_count && min_count > 0
                  json_schema["properties"][prop_name]["maxItems"] = max_count if max_count
                end
              end

              JSON.pretty_generate(json_schema)
            end

            def every_entity(data)
              all_references = []
              graph_prefix = data[:ontologies][:base][:prefix]
              data[:entities].map do |entity_name, metadata|
                table_name = metadata[:plural].to_s.underscore
                table_comment = metadata[:description]&.gsub('\'', '')&.gsub(/\n|\r/, ' ')

                properties = metadata[:properties].map do |name, property_metadata|
                  raise Solis::Error::NotFoundError, "A property in the #{entity_name} tab is empty #{metadata[:properties].to_json}" if name.empty?

                  is_fk = property_metadata[:datatype].split(':').first.eql?(data[:ontologies][:base][:prefix].to_s) ? true : false

                  if property_metadata.key?(:datatype) && property_metadata[:datatype].empty?
                    raise Solis::Error::NotFoundError,
                          "#{entity_name}.#{name} Has no datatype"
                  end

                  if data[:entities][property_metadata[:datatype].split(':').last.to_sym].nil? && is_fk
                    raise Solis::Error::NotFoundError,
                          "#{entity_name}.#{name} Not found in _ENTITIES tab"
                  end

                  if is_fk
                    references = data[:entities][property_metadata[:datatype].split(':').last.to_sym][:plural].to_s.underscore
                  end
                  mandatory = property_metadata[:cardinality][:min].to_i > 0
                  datatype = datatype_lookup(property_metadata[:datatype], :sql)

                  column_name = "#{name}#{is_fk ? '_id' : ''}"

                  {
                    schema: graph_prefix,
                    name: name,
                    column_name: column_name,
                    column: lambda { |type = :uml|
                      out = ''
                      case type
                      when :sql
                        if name.to_s.eql?('id')
                          out += "\t#{column_name} SERIAL#{mandatory ? ' NOT NULL' : ''} PRIMARY KEY"
                        else
                          out += "\t#{column_name} #{is_fk ? 'int' : datatype}#{mandatory ? ' NOT NULL' : ''}#{is_fk ? " REFERENCES #{graph_prefix}.#{references}(id)" : ''}"
                        end

                      else
                        cardinality_min = { '0' => '|o', '' => '}o', '1' => '||' }
                        cardinality_max = { '0' => 'o|', '' => 'o{', '1' => '||' }

                        if name.to_s.eql?('id')
                          out += "\t *#{name} : #{datatype} <<generated>>\n"
                          out += "--\n"
                        else
                          out += "\t #{mandatory ? '*' : ''}#{column_name} : #{datatype} #{is_fk ? '<<FK>>' : ''}"
                        end

                        relations = []
                        if property_metadata[:datatype].split(':').first.eql?(graph_prefix.to_s)
                          cmin = cardinality_min[(property_metadata[:cardinality][:min]).to_s]
                          cmax = cardinality_max[(property_metadata[:cardinality][:max]).to_s]

                          ref_table_name = [property_metadata[:datatype].split(':').last.to_sym,
                                            property_metadata[:path].split(':').last.classify.to_sym].map do |m|
                            data[:entities][m].nil? ? nil : data[:entities][m][:plural].underscore
                          end.compact.first

                          relations << "#{table_name} #{cmin}--#{cmax} #{ref_table_name} "
                        end
                        out = { out: out, relations: relations, references: references }
                      end

                      out
                    },
                    type: datatype,
                    foreign_key: is_fk,
                    mandatory: mandatory,
                    references: references,
                    cardinality: property_metadata[:cardinality],
                    comment: property_metadata[:description]&.gsub('\'', '')&.gsub(/\n|\r/, ' ')
                  }
                end

                {
                  table: lambda { |type = :uml|
                    out = ''
                    case type
                    when :sql
                      out = "CREATE TABLE #{graph_prefix}.#{table_name}(\n"
                      properties.each_with_index do |property, i|
                        out += ", \n" if i > 0
                        out += property[:column].call(type)
                        all_references << property[:references]
                      end
                      out += "\n);\n"

                      unless table_comment.nil? || table_comment.empty?
                        out += "COMMENT ON TABLE #{graph_prefix}.#{table_name} '#{table_comment}';\n"
                      end

                      properties.each_with_index do |property, i|
                        if property.key?(:comment) && !property[:comment].empty?
                          out += "COMMENT ON COLUMN #{graph_prefix}.#{table_name}.#{property[:column_name]} IS '#{property[:comment]}';\n"
                        end
                      end

                      out = { out: out, references: all_references.compact.sort.each_with_object(Hash.new(0)) { |o, h| h[o] += 1 } }
                    else
                      out += "entity \"#{table_name}\" as #{table_name}"
                      unless properties.nil? || properties.empty?
                        out += "{\n"
                        relations = []
                        properties.each_with_index do |property, i|
                          d = property[:column].call(:uml)
                          out += "\n" if i > 1
                          out += d[:out]
                          relations += d[:relations]
                          all_references << property[:references]
                        end
                        out += "\n}\n"
                        out = { out: out, relations: relations }
                      end
                    end

                    out
                  },
                  schema: graph_prefix,
                  entity_name: entity_name,
                  name: table_name,
                  comment: table_comment,
                  properties: properties
                }
              end
            end

            def header(data)
              out = data[:ontologies][:all].map do |k, v|
                "@prefix #{k}: <#{v[:uri]}> ."
              end.join("\n")

              "#{out}\n"
            end

            def spreadsheet_id_from_url(sheet_url)
              tmp = URI(sheet_url).path.split('/')
              spreadsheet_id = tmp[tmp.index('d') + 1]
            end
          end

          sheet_data = read_sheets(key, spreadsheet_id, options)
          prefixes = sheet_data['_PREFIXES']
          metadata = sheet_data['_METADATA']

          raise "_PREFIXES tab must have ['base', 'prefix', 'uri'] as a header at row 1" unless (%w[base prefix uri] - prefixes.header).length == 0
          raise '_PREFIXES.base can only have one base URI' if prefixes.map { |m| m['base'] }.grep(/\*/).count != 1

          raise "_METADATA tab must have ['key', 'value'] as a header at row 1" unless (%w[key value] - metadata.header).length == 0

          options[:prefixes] = prefixes
          options[:metadata] = metadata
          #TODO: cleanup
          if sheet_data.is_a?(Hash)
            raise "No _REFERENCES sheet found" unless sheet_data.key?("_REFERENCES")
            # read other ontologies
            Solis::LOGGER.info('Reading referenced ontologies')
            references = sheet_data['_REFERENCES'].map do |reference|
              { sheet_url: reference['sheeturl'], description: reference['description'] }
            end

            cache_dir = ConfigFile.include?(:cache) ? ConfigFile[:cache] : '/tmp'
            ::File.open("#{::File.absolute_path(cache_dir)}/#{spreadsheet_id}.json", 'wb') do |f|
              f.puts references.to_json
            end
          else
            references = sheet_data
          end

          datas = []
          references.each_with_index do |v, i|
            progress((100/(references.length+1))*(i+1), options[:progress] || {})
            sheet_id = spreadsheet_id_from_url(v[:sheet_url])

            sheet_data = read_sheets(key, sheet_id, options)

            unless sheet_data.key?('_PREFIXES')
              sheet_data['_PREFIXES'] = prefixes
            end

            unless sheet_data.key?('_METADATA')
              sheet_data['_METADATA'] = metadata
            end

            if sheet_data.key?("_PREFIXES")
              datas << process_sheet(key, sheet_id, sheet_data)
              sleep 30
            else
              datas << sheet_data
            end
          end

          Solis::LOGGER.info('Generating SHACL')
          shacl = build_shacl(datas)
          Solis::LOGGER.info('Generating PLANTUML')
          plantuml = build_plantuml(datas)
          Solis::LOGGER.info('Generating SCHEMA')
          schema = build_schema(datas)
          Solis::LOGGER.info('Generating INFLECTIONS')
          inflections = build_inflections(datas)
          Solis::LOGGER.info('Generating JSON SCHEMA')
          json_schema = build_json_schema(shacl)

          { inflections: inflections, shacl: shacl, schema: schema, plantuml: plantuml, json_schema: json_schema }
        end
      end
    end
  end
end
