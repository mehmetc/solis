require_relative 'simple_sheets'
require 'active_support/all'
require 'active_support/hash_with_indifferent_access'
require 'rdf/vocab'

module Solis
  module Shape
    module Reader
      class Sheet
        def self.read(key, spreadsheet_id, options = {})
          class << self
            def validate(sheets)
              raise "Please make sure the sheet contains '_PREFIXES', '_METADATA', '_ENTITIES' tabs" unless (%w[
                _PREFIXES _METADATA _ENTITIES
              ] - sheets.keys).length == 0

              prefixes = sheets['_PREFIXES']
              metadata = sheets['_METADATA']
              entities = sheets['_ENTITIES']

              raise "_PREFIXES tab must have ['base', 'prefix', 'uri'] as a header at row 1" unless (%w[base prefix
                                                                                                        uri] - prefixes.header).length == 0
              raise "_METADATA tab must have ['key', 'value'] as a header at row 1" unless (%w[key
                                                                                               value] - metadata.header).length == 0
              raise "_ENTITIES tab must have ['name', 'nameplural', 'description', 'subclassof', 'sameas'] as a header at row 1" unless (%w[
                name nameplural description subclassof sameas
              ] - entities.header).length == 0

              raise '_PREFIXES.base can only have one base URI' if prefixes.map { |m| m['base'] }.grep(/\*/).count != 1
            end

            def read_sheets(key, spreadsheet_id, options)
              data = nil

              cache_dir = ConfigFile.include?(:solis) && ConfigFile[:solis].include?(:cache) ? ConfigFile[:solis][:cache] : '/tmp'

              if ::File.exist?("#{cache_dir}/#{spreadsheet_id}.json") && (options.include?(:from_cache) && options[:from_cache])
                Solis::LOGGER.info("from cache #{cache_dir}/#{spreadsheet_id}.json")
                data = JSON.parse(::File.read("#{cache_dir}/#{spreadsheet_id}.json"), { symbolize_names: true })
              else
                Solis::LOGGER.info("from source #{spreadsheet_id}")
                session = SimpleSheets.new(key, spreadsheet_id)
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

                sheets['_PREFIXES'].each do |e|
                  prefixes.store(e['prefix'].to_sym, { uri: e['uri'], base: e['base'].eql?('*') })
                end
                sheets['_METADATA'].each { |e| ontology_metadata.store(e['key'].to_sym, e['value']) }

                base_uri = prefixes.select { |_k, v| v[:base] }.select { |s| !s.empty? }

                graph_prefix = base_uri.keys.first
                graph_name = base_uri.values.first[:uri]

                sheets['_ENTITIES'].each do |e|

                  top_class = e['name'].to_s
                  # subclassof = e['subclassof'].empty? ? nil : e['subclassof'].split(':').last
                  # while subclassof                                        
                  #   candidate_sco = sheets['_ENTITIES'].select{|t| t['name'].eql?(subclassof)}.first
                  #   subclassof = candidate_sco['subclassof'].empty? ? nil : candidate_sco['subclassof'].split(':').last
                  #   top_class = candidate_sco['name'].to_s if candidate_sco['subclassof'].empty?
                  # end
                  
              
                  entity_data = parse_entity_data(e['name'].to_s, graph_prefix, graph_name, sheets[top_class])

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

                ::File.open("#{cache_dir}/#{spreadsheet_id}.json", 'wb') do |f|
                  f.puts data.to_json
                end
              end

              data
            rescue StandardError => e
              raise Solis::Error::GeneralError, e.message
            end

            def parse_entity_data(name, graph_prefix, _graph_name, e)
              properties = {}
              entity_data = e
              if entity_data && !entity_data.nil? && (entity_data.count > 0)
                entity_data.each do |p|
                  min_max = {}

                  %w[min max].each do |n|
                    min_max[n] = if p.key?(n) && p[n] =~ /\d+/
                                   p[n].to_i.to_s
                                 else
                                   ''
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

              properties
            end

            def build_plantuml(data)
              out = %(@startuml
!pragma layout elk
skinparam classFontSize 14
!define LIGHTORANGE
skinparam groupInheritance 1
skinparam componentStyle uml2
skinparam wrapMessageWidth 100
skinparam ArrowColor #Maroon

title #{data[:metadata][:title]} - #{data[:metadata][:version]} - #{Time.now}
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
                'xsd:string' => { sql: 'text' },
                'xsd:date' => { sql: 'date' },
                'xsd:boolean' => { sql: 'bool' },
                'xsd:integer' => { sql: 'integer' }
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

title #{data[:metadata][:title]} - #{data[:metadata][:version]} - #{Time.now}
              )

              out += "\npackage #{data[:ontologies][:base][:prefix]} {\n"
              relations = []
              data[:entities].each do |_entity_name, metadata|
                table_name = metadata[:plural].to_s.underscore
                # out += "\nentity \"#{entity_name}\" as #{table_name}"
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
                      mandatory = property_metadata[:cardinality][:min].to_i > 0
                      is_fk = property_metadata[:datatype].split(':').first.eql?(data[:ontologies][:base][:prefix].to_s) ? true : false
                      out += "\t #{mandatory ? '*' : ''}#{property}#{is_fk ? '_id' : ''} : #{datatype_lookup(
                        property_metadata[:datatype], :sql
                      )} #{is_fk ? '<<FK>>' : ''} \n"
                    end

                    unless property_metadata[:datatype].split(':').first.eql?(data[:ontologies][:base][:prefix].to_s)
                      next
                    end

                    cmin = cardinality_min[(property_metadata[:cardinality][:min]).to_s]
                    cmax = cardinality_max[(property_metadata[:cardinality][:max]).to_s]

                    # relations << " #{entity_name.to_s.underscore} #{cmin}--o{ #{property_metadata[:datatype].split(':').last.to_s.underscore} "
                    # ref_table_name = property_metadata[:datatype].split(':').last.to_s.underscore
                    ref_table_name = [property_metadata[:datatype].split(':').last.to_sym,
                                      property_metadata[:path].split(':').last.classify.to_sym].map do |m|
                      data[:entities][m].nil? ? nil : data[:entities][m][:plural].underscore
                    end.compact.first

                    relations << " #{table_name} #{cmin}--#{cmax} #{ref_table_name} "
                  end
                  out += "}\n"
                end

                out += "\n"
                # out += "#{entity_name} }o-- #{metadata[:sub_class_of].split(':').last}\n" unless metadata[:sub_class_of].empty?
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
              shacl_prefix = data[:ontologies][:all].select { |_, v| v[:uri] =~ /shacl/ }.keys.first
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
                  node += 'Shape' if node != /Shape$/ && node =~ /^#{graph_prefix}:/
                else
                  node = target_class
                end

                out += %(
#{graph_prefix}:#{entity_name}Shape
    a               #{shacl_prefix}:NodeShape ;
    #{shacl_prefix}:description "#{description&.gsub('"', "'")&.gsub(/\n|\r/, '')}" ;
    #{shacl_prefix}:targetClass  #{target_class} ;#{unless node.nil? || node.empty?
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
              data[:ontologies][:all].each { |k, v| all_prefixes[k] = v[:uri] }

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

              lp = RDF::StrictVocabulary(graph_name)
              o = ::Class.new(lp) do
                ontology(graph_name.to_sym, {
                           "dc11:title": data[:metadata][:title].freeze,
                           "dc11:description": data[:metadata][:description].freeze,
                           "dc11:date": Time.now.to_s.freeze,
                           "dc11:creator": data[:metadata][:author].freeze,
                           "owl:versionInfo": data[:metadata][:version].freeze,
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

              data[:entities].select { |_k, v| !v[:same_as].empty? }.each do |k, v|
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
              out = "--\n-- #{data[:metadata][:title]} - #{data[:metadata][:version]} - #{Time.now}\n"
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
                  mandatory = property_metadata[:cardinality][:min].to_i > 0
                  is_fk = property_metadata[:datatype].split(':').first.eql?(data[:ontologies][:base][:prefix].to_s) ? true : false
                  if data[:entities][property_metadata[:datatype].split(':').last.to_sym].nil? && is_fk
                    raise Solis::Error::NotFoundError,
                          "#{entity_name}.#{property} Not found in _ENTITIES tab"
                  end

                  if is_fk
                    references = data[:entities][property_metadata[:datatype].split(':').last.to_sym][:plural].to_s.underscore
                  end

                  out += ", \n" if i > 0
                  if property.to_s.eql?('id')
                    # out += "\t#{property} #{datatype_lookup(property_metadata[:datatype], :sql)}#{mandatory ? ' NOT NULL' : ''} PRIMARY KEY"
                    out += "\t#{property} SERIAL#{mandatory ? ' NOT NULL' : ''} PRIMARY KEY"
                  else
                    out += "\t#{property}#{is_fk ? '_id' : ''} #{datatype_lookup(property_metadata[:datatype],
                                                                                 :sql)}#{mandatory ? ' NOT NULL' : ''}#{is_fk ? " REFERENCES #{graph_prefix}.#{references}(id)" : ''}"
                  end
                end

                out += ");\n\n"
              end

              out
            end

            def build_erd(data, type = :uml)
              out = erd_header(data, type)
              all_tables = {}
              tables = {}
              relations = []
              references = {}
              every_entity(data).each do |table|
                case type
                when :uml
                  d = table[:table].call(type)
                  out += d[:out]
                  relations << d[:relations] unless d[:relations].empty?
                  out += "\n\n"
                  #references << d[:references]
                when :sql
                  all_tables[table[:name]] = table
                  d = table[:table].call(type)
                  tables[table[:name]] = d[:out]
                  
                  d[:references].each do |k,v|                    
                    references[k] = (references.include?(k) ? references[k] : 0) + v
                  end
                end                        
              end

              references = references.sort_by{|k,v| -v }.to_h #each{|m| r[m[0]] = m[1]}

              r=references.sort_by{|k,v| 
                k = k[0]                
                relation =  all_tables.key?(k) ?  all_tables[k][:properties].map{|s| s[:references]}.compact.first : nil
                
                a = references.keys.index(k) 
                b = references.keys.index(relation) 
                b = 0 if b.nil?
                a = 0 if a.nil?             

                b = a + b if b < a 
                
                b
              }

              references = r.to_h
              
              
              if type.eql?(:sql)
                all_keys = references.keys
                t = tables.sort_by{|k,v| all_keys.include?(k) ? all_keys.index(k) : 0 }
                out += t.map{|m| m[1]}.join("\n")
              end

              #              ::File.open("#{ConfigFile[:cache]}/test.json", 'wb') {|f| f.puts references.to_json}

              out += relations.sort.uniq.join("\n")
              out += erd_footer(data, type)
              
              
              out
            end

            def erd_header(data, type)
              header = ''

              case type
              when :uml
                header = %(@startuml
skinparam classFontSize 14
!define LIGHTORANGE
skinparam groupInheritance 1
skinparam componentStyle uml2
skinparam wrapMessageWidth 100
skinparam ArrowColor #Maroon
skinparam linetype ortho

title #{data[:metadata][:title]} - #{data[:metadata][:version]} - #{Time.now}

package #{data[:ontologies][:base][:prefix]} {
)
              when :sql
                graph_prefix = data[:ontologies][:base][:prefix]
                header = %(--
-- #{data[:metadata][:title]} - #{data[:metadata][:version]} - #{Time.now}
-- description: #{data[:metadata][:description]}
-- author: #{data[:metadata][:author]}
--


CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
DROP SCHEMA IF EXISTS #{graph_prefix} CASCADE;
CREATE SCHEMA #{graph_prefix};


)
              end

              header
            end

            def erd_footer(_data, type = :uml)
              footer = ''

              case type
              when :uml
                footer = %(

hide circle
hide methods
hide empty members
@enduml
)
              when :sql
                footer = ''
              end

              footer
            end

            def every_entity(data)
              all_references = []
              graph_prefix = data[:ontologies][:base][:prefix]
              data[:entities].map do |entity_name, metadata|
                table_name = metadata[:plural].to_s.underscore
                table_comment = metadata[:description]&.gsub('\'', '')&.gsub(/\n|\r/,' ')

                properties = metadata[:properties].map do |name, property_metadata|
                  is_fk = property_metadata[:datatype].split(':').first.eql?(data[:ontologies][:base][:prefix].to_s) ? true : false

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
                                out = {out: out, relations: relations, references: references}
                              end

                              out
                            },
                    type: datatype,
                    foreign_key: is_fk,
                    mandatory: mandatory,
                    references: references,
                    cardinality: property_metadata[:cardinality],
                    comment: property_metadata[:description]&.gsub('\'', '')&.gsub(/\n|\r/,' ')
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

                      out = {out: out, references: all_references.compact.sort.each_with_object(Hash.new(0)) { |o, h| h[o] += 1 }}
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
                        out = {out: out, relations: relations}
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
          end

          data = read_sheets(key, spreadsheet_id, options)

          shacl = build_shacl(data)
          plantuml = build_plantuml(data)
          #plantuml_erd = build_plantuml_erd(data)
          plantuml_erd = build_erd(data, :uml)
          schema = build_schema(data)
          inflections = build_inflections(data)
          sql = build_erd(data, :sql)
          #erd = build_erd(data, :uml)
          { inflections: inflections, shacl: shacl, schema: schema, plantuml: plantuml,
            plantuml_erd: plantuml_erd, sql: sql }
        end
      end
    end
  end
end
