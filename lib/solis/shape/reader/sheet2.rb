require 'simple_sheets'
require 'active_support/all'
require 'active_support/hash_with_indifferent_access'
require 'rdf/vocab'

module Solis
  module Shape
    module Reader
      class Sheet
        def self.read(key, spreadsheet_id)
          class << self
            def validate(sheets)
              raise "Please make sure the sheet contains '_PREFIXES', '_METADATA', '_ENTITIES' tabs" unless (['_PREFIXES', '_METADATA', '_ENTITIES'] - sheets.keys).length == 0

              prefixes = sheets['_PREFIXES']
              metadata = sheets['_METADATA']
              entities = sheets['_ENTITIES']

              raise "_PREFIXES tab must have ['base', 'prefix', 'uri'] as a header at row 1" unless (["base", "prefix", "uri"] - prefixes.header).length == 0
              raise "_METADATA tab must have ['key', 'value'] as a header at row 1" unless (["key", "value"] - metadata.header).length == 0
              raise "_ENTITIES tab must have ['name', 'nameplural', 'description', 'subclassof', 'sameas'] as a header at row 1" unless (["name", "nameplural", "description", "subclassof", "sameas"] - entities.header).length == 0

              raise "_PREFIXES.base can only have one base URI" if (prefixes.map{|m| m['base']}.grep(/\*/)).count != 1

            end

            def read_sheets(key, spreadsheet_id)
              data = nil
              if ::File.exist?('./sheet.json') && ENV['DEBUG'].eql?('1')
                puts "from cache"
                data = JSON.parse(::File.read('./sheet.json'), {symbolize_names: true})
              else
                puts "from source"
                session = SimpleSheets.new(spreadsheet_id)
                session.key = key
                sheets = {}
                session.worksheets.each do |worksheet|
                  sheet = ::Sheet.new(worksheet)
                  sheets[sheet.title] = sheet
                end

                validate(sheets)

                entities = {}
                prefixes = {}
                ontology_metadata = {}

                sheets['_PREFIXES'].each { |e| prefixes.store(e['prefix'].to_sym, { uri: e['uri'], base: e['base'].eql?('*') }) }
                sheets['_METADATA'].each { |e| ontology_metadata.store(e['key'].to_sym, e['value']) }

                base_uri = prefixes.select { |k, v| v[:base] }.select { |s| !s.empty? }

                graph_prefix = base_uri.keys.first
                graph_name = base_uri.values.first[:uri]

                sheets['_ENTITIES'].each do |e|
                  entity_data = parse_entity_data(e['name'].to_s, graph_prefix, graph_name, sheets[e['name'].to_s])

                  if entity_data.empty?
                    entity_data[:id] = {
                      datatype: 'xsd:string',
                      path: "#{graph_prefix}:id",
                      cardinality: { min: '1', max: '1' },
                      same_as: '',
                      description: "systeem UUID"
                    }
                  end

                  entities.store(e['name'].to_sym, { description: e['description'],
                                                     plural: e['nameplural'],
                                                     sub_class_of: e['subclassof'].nil? || e['subclassof'].empty? ? [] : [e['subclassof']] ,
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

                ::File.open("sheet.json", "wb") do |f|
                  f.puts data.to_json
                end
              end

              data
            rescue StandardError => e
              raise Solis::Error::GeneralError, e.message
            end

            def parse_entity_data(name, graph_prefix, graph_name, e)
              properties = {}
              entity_data = e
              if entity_data && !entity_data.nil?
                if entity_data.count > 0
                  entity_data.each do |p|
                    min_max = {}

                    ['min', 'max'].each do |n|
                      if p.key?(n) && p[n] =~/\d+/
                        min_max[n] = "#{p[n].to_i}"
                      else
                        min_max[n] = ''
                      end
                    end

                    properties[p['name'].strip] = {
                      datatype: p['datatype'],
                      path: "#{graph_prefix}:#{p['name'].to_s.classify}",
                      cardinality: { min: min_max['min'], max: min_max['max'] },
                      same_as: p['sameAs'],
                      description: p['description']
                    }
                  end
                end
              end

              properties
            end

            def build_plantuml(data)
              out = %(@startuml
skinparam classFontSize 14
!define LIGHTORANGE
skinparam groupInheritance 1
skinparam componentStyle uml2
skinparam wrapMessageWidth 100
skinparam ArrowColor #Maroon

title #{data[:metadata][:title]} - #{data[:metadata][:version]} - #{Time.now.to_s}
              )

              out += "\npackage #{data[:ontologies][:base][:prefix]} {\n"
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

              out += %(
hide circle
hide methods
hide empty members
@enduml
          )


              out
            end

            def datatype_lookup(datatype, as = :sql)
              datatypes = {
                "xsd:string" => { sql: 'text' },
                "xsd:date" => {sql: 'date'},
                "xsd:boolean" => {sql: 'bool'},
                "xsd:integer" => {sql: 'integer'}
              }

              datatypes.default = { sql: 'text' }

              datatypes[datatype][as]
            end

            def build_plantuml_erd(data)
              cardinality_min = { '0' => '|o', '' => '}o', '1' => '||' }
              cardinality_max = { '0' => 'o|', '' => 'o{', '1' => '||' }

              out = %(@startuml
skinparam classFontSize 14
!define LIGHTORANGE
skinparam groupInheritance 1
skinparam componentStyle uml2
skinparam wrapMessageWidth 100
skinparam ArrowColor #Maroon
skinparam linetype ortho

title #{data[:metadata][:title]} - #{data[:metadata][:version]} - #{Time.now.to_s}
              )

              out += "\npackage #{data[:ontologies][:base][:prefix]} {\n"
              relations = []
              data[:entities].each do |entity_name, metadata|
                table_name = metadata[:plural].to_s.underscore
                #out += "\nentity \"#{entity_name}\" as #{table_name}"
                out += "\nentity \"#{table_name}\" as #{table_name}"

                properties = metadata[:properties]
                # relations = []
                unless properties.nil? || properties.empty?
                  out += "{\n"
                  properties.each do |property, property_metadata|
                    if property.to_s.eql?('id')
                      out += "\t *#{property} : #{datatype_lookup(property_metadata[:datatype], :sql)} <<generated>>\n"
                      out += "--\n"
                    else
                      mandatory = property_metadata[:cardinality][:min].to_i > 0 ? true : false
                      is_fk= property_metadata[:datatype].split(':').first.eql?(data[:ontologies][:base][:prefix].to_s) ? true : false
                      out += "\t #{mandatory ? '*' : ''}#{property}#{is_fk ? '_id' : ''} : #{datatype_lookup(property_metadata[:datatype], :sql)} #{is_fk ? '<<FK>>' : '' } \n"
                    end

                    if property_metadata[:datatype].split(':').first.eql?(data[:ontologies][:base][:prefix].to_s)
                      cmin = cardinality_min["#{property_metadata[:cardinality][:min]}"]
                      cmax = cardinality_max["#{property_metadata[:cardinality][:max]}"]

                      #relations << " #{entity_name.to_s.underscore} #{cmin}--o{ #{property_metadata[:datatype].split(':').last.to_s.underscore} "
                      #ref_table_name = property_metadata[:datatype].split(':').last.to_s.underscore
                      ref_table_name = [property_metadata[:datatype].split(':').last.to_sym, property_metadata[:path].split(':').last.classify.to_sym].map do |m|
                        data[:entities][m].nil? ? nil : data[:entities][m][:plural].underscore
                      end.compact.first

                      relations << " #{table_name} #{cmin}--#{cmax} #{ref_table_name} "
                     end
                  end
                  out += "}\n"
                end



                out += "\n"
                #out += "#{entity_name} }o-- #{metadata[:sub_class_of].split(':').last}\n" unless metadata[:sub_class_of].empty?

              end
              out += relations.join("\n")

              out += %(
hide circle
hide methods
hide empty members
@enduml
          )

              out
            end

            def build_shacl(data)
              shacl_prefix = data[:ontologies][:all].select{|_, v| v[:uri] =~ /shacl/}.keys.first
              shacl_prefix = 'sh' if shacl_prefix.nil?

              out = header(data)

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
                  node += "Shape" if node != /Shape$/ && node =~ /^#{graph_prefix}:/
                else
                  node = target_class
                end

                out += %(
#{graph_prefix}:#{entity_name}Shape
    a               #{shacl_prefix}:NodeShape ;
    #{shacl_prefix}:description "#{description&.gsub('"', "'")&.gsub(/\n|\r/, '')}" ;
    #{shacl_prefix}:targetClass  #{target_class} ;#{"\n    #{shacl_prefix}:node         #{node} ;" unless node.nil? || node.empty?}
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
                    out += %(    #{shacl_prefix}:property [#{shacl_prefix}:path #{datatype} ;
                 #{shacl_prefix}:name "#{attribute}" ;
                 #{shacl_prefix}:description "#{description}" ;
                 #{shacl_prefix}:nodeKind #{shacl_prefix}:IRI ;
                 #{shacl_prefix}:class    #{datatype} ;#{min_count =~ /\d+/ ? "\n                 #{shacl_prefix}:minCount #{min_count} ;" : ''}#{max_count =~ /\d+/ ? "\n                 #{shacl_prefix}:maxCount #{max_count} ;" : ''}
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
                out += ".\n"
              end

              out
            end

            def build_schema(data)
              classes = {}
              datatype_properties = {}
              object_properties = {}

              format = :ttl
              graph_prefix = data[:ontologies][:base][:prefix]
              graph_name = data[:ontologies][:base][:uri]

              all_prefixes = {}
              data[:ontologies][:all].each{|k,v| all_prefixes[k] = v[:uri]}

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
                  domain << "#{graph_name}#{entity_name.to_s}"
                  datatype_properties[attribute] = {
                    domain: domain,
                    comment: description,
                    label: "#{attribute.to_s}",
                    range: datatype,
                    type: 'rdf:Property'
                  }
                  datatype_properties[attribute]['owl:sameAs'] = property_metadata[:same_as] unless property_metadata[:same_as].nil? || property_metadata[:same_as].empty?

                  subclass_data = data[:entities][entity_name][:sub_class_of] || []
                  unless property_metadata[:cardinality][:min].empty?
                    subclass_data << RDF::Vocabulary.term(type: "owl:Restriction",
                                                          onProperty: path,
                                                          minCardinality: property_metadata[:cardinality][:min])
                  end
                  unless property_metadata[:cardinality][:max].empty?
                    subclass_data << RDF::Vocabulary.term(type: "owl:Restriction",
                                                          onProperty: path,
                                                          maxCardinality: property_metadata[:cardinality][:max])
                  end
                  data[:entities][entity_name][:sub_class_of] = subclass_data
                end
              end

              lp = RDF::StrictVocabulary(graph_name)
              o = ::Class.new(lp) do
                ontology(graph_name.to_sym, {
                  "dc11:title": data[:metadata][:title].freeze,
                  "dc11:description": data[:metadata][:description].freeze,
                  "dc11:date": "#{Time.now.to_s}".freeze,
                  "dc11:creator": data[:metadata][:author].freeze,
                  "owl:versionInfo": data[:metadata][:version].freeze,
                  type: "owl:Ontology".freeze
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

              data[:entities].select { |k, v| !v[:same_as].empty? }.each do |k, v|
                prefix, verb = v[:same_as].split(':')
                rdf_vocabulary = RDF::Vocabulary.from_sym(prefix.upcase)
                rdf_verb = rdf_vocabulary[verb.to_sym]
                graph << RDF::Statement.new(rdf_verb, RDF::RDFV.type, RDF::OWL.Class)
                graph << RDF::Statement.new(rdf_verb, RDF::Vocab::OWL.sameAs, o[k.to_sym])
              end

              graph << o.to_enum

              graph.dump(format, prefixes: all_prefixes)
            end

            def build_inflections(data)
              inflections = {}
              data[:entities].each do |entity, metadata|
                inflections[entity.to_s.underscore.to_sym] = metadata[:plural].underscore
              end

              inflections.to_json
            end

            def build_sql(data)
              graph_prefix = data[:ontologies][:base][:prefix]
              out = "--\n-- #{data[:metadata][:title]} - #{data[:metadata][:version]} - #{Time.now.to_s}\n"
              out += "-- description: #{data[:metadata][:description]}\n"
              out += "-- author: #{data[:metadata][:author]}\n--\n\n"

              out += %(CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
DROP SCHEMA IF EXISTS #{graph_prefix} CASCADE;
CREATE SCHEMA #{graph_prefix};

)
              data[:entities].each do |entity_name, metadata|
                table_name = metadata[:plural].to_s.underscore
                out += "CREATE TABLE #{graph_prefix}.#{table_name}(\n"

                properties = metadata[:properties]
                properties.each_with_index do |(property, property_metadata), i|
                  mandatory = property_metadata[:cardinality][:min].to_i > 0 ? true : false
                  is_fk= property_metadata[:datatype].split(':').first.eql?(data[:ontologies][:base][:prefix].to_s) ? true : false
                  raise Solis::Error::NotFoundError, "#{entity_name}.#{property} Not found in _ENTITIES tab" if data[:entities][property_metadata[:datatype].split(':').last.to_sym].nil? && is_fk
                  references = data[:entities][property_metadata[:datatype].split(':').last.to_sym][:plural].to_s.underscore if is_fk

                  out += ", \n" if i > 0
                  if property.to_s.eql?('id')
                    #out += "\t#{property} #{datatype_lookup(property_metadata[:datatype], :sql)}#{mandatory ? ' NOT NULL' : ''} PRIMARY KEY"
                    out += "\t#{property} SERIAL#{mandatory ? ' NOT NULL' : ''} PRIMARY KEY"
                  else
                    out += "\t#{property}#{is_fk ? '_id' : ''} #{datatype_lookup(property_metadata[:datatype], :sql)}#{mandatory ? ' NOT NULL' : ''}#{is_fk ? " REFERENCES #{graph_prefix}.#{references}(id)" : ''}"
                  end
                end

                out += ");\n\n"
              end

              out
            end

            def header(data)
              out = data[:ontologies][:all].map{|k,v|
                "@prefix #{k.to_s}: <#{v[:uri]}> ."
              }.join("\n")

              "#{out}\n"
            end
          end

          data = read_sheets(key, spreadsheet_id)

          shacl = build_shacl(data)
          plantuml = build_plantuml(data)
          plantuml_erd = build_plantuml_erd(data)
          schema = build_schema(data)
          inflections = build_inflections(data)
          sql = build_sql(data)
          { inflections: inflections, shacl: shacl, schema: schema, plantuml: plantuml, plantuml_erd: plantuml_erd, sql:  sql}
        end

      end
    end
  end
end
