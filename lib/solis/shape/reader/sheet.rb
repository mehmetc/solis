require 'simple_sheets'
require 'active_support/all'
require 'rdf/vocab'

module Solis
  module Shape
    module Reader
      class Sheet
        attr_reader :key, :session, :sheets, :shapes, :prefixes, :ontology_metadata

        def initialize(key)
          @key = key
          @sheets = {}
          @shapes = {}
          @prefixes = {}
          @ontology_metadata = {}
        end

        def read(spreadsheet_id)
          @session = SimpleSheets.new(spreadsheet_id)
          @session.key = key
          @sheets = {}
          @session.worksheets.each do |worksheet|
            sheet = ::Sheet.new(worksheet)
            @sheets[sheet.title] = sheet
          end
          @shapes = {}
          @prefixes = []
          @ontology_metadata = {}
          @sheets['_ENTITIES'].each { |e| @shapes.store(e['name'].to_sym, { description: e['description'], target_class: e['subclassof'], same_as: e['sameas'] }) }
          @sheets['_PREFIXES'].each { |e| @prefixes << { e['prefix'].to_sym => { uri: e['uri'], base: e['base'].eql?('*') } } }
          @sheets['_METADATA'].each { |e| @ontology_metadata.store(e['key'].to_sym, e['value']) }

          process(graph_prefix, graph_uri)
        end

        private

        def base_ontology
          @base_ontology ||= begin
                               temp = @prefixes.map { |m| m.select { |k, v| v[:base] } }.select { |s| !s.empty? }
                               raise 'There can only be 1 URI' if temp.size > 1
                               temp.first
                             end
        end

        def graph_prefix
          base_ontology.keys.first
        end

        def graph_uri
          base_ontology.values.first[:uri]
        end

        def all_prefixes(base = true)
          p = {}
          prefixes.each do |k|
            next if k.values.first[:base] && !base

            p.store(k.keys.first, k.values.first[:uri])
          end
          p
        end

        def process(graph_prefix, graph_uri)
          shapes = build_shapes(self, graph_prefix, graph_uri)
          schema = build_schema(self, graph_prefix, graph_uri)
          plantuml = build_plantuml(self, graph_prefix, graph_uri)
          inflections = build_inflections(self)

          schema_graph = RDF::Graph.new
          schema_graph.name = RDF::URI(graph_uri)
          schema_graph.from_ttl(schema)

          shapes_graph = RDF::Graph.new
          shapes_graph.name = RDF::URI(graph_uri)
          shapes_graph.from_ttl(shapes)
          shape_shapes = SHACL.get_shapes(shapes_graph)

          { inflections: inflections, shapes: shapes, schema: schema, gshapes: shape_shapes, gschema: schema_graph, plantuml: plantuml }
        end

        def header(graph_prefix, graph_name)
          all_prefixes.map { |k, v| "@prefix #{k}: <#{v}> ." }.join("\n")
        end

        def build_classes(classes, metadata, shape_name)
          classes[shape_name] = {
            comment: metadata[:description]&.gsub('"', "'")&.gsub(/\n|\r/, ' '),
            label: shape_name.to_s.strip,
            type: 'owl:Class'
          }

          classes[shape_name][:subClassOf] = [metadata[:target_class]] unless metadata[:target_class].empty?
          #classes[metadata[:same_as]] = {type: 'owl:Class', 'owl:sameAs' =>  [":#{shape_name}"]} if metadata.key?(:same_as) && !metadata[:same_as].empty? && !metadata[:same_as].nil?
        end

        def build_shapes(g, graph_prefix, graph_name)
          shacl_prefix = all_prefixes.select { |_, v| v =~ /shacl/ }.keys.first
          shacl_prefix = 'sh' if shacl_prefix.nil?

          format = :ttl
          classes = {}

          out = header(graph_prefix, graph_name)
          g.shapes.each do |shape_name, metadata|
            build_classes(classes, metadata, shape_name)
          end

          classes.each do |klass, metadata|
            puts klass
            description = metadata[:comment]
            label = metadata[:label]
            target_class = "#{graph_prefix}:#{klass}"
            node = metadata[:subClassOf]
            if node
              node = node.first if node.is_a?(Array)
              node = node.strip
              node += "Shape" if node !~ /Shape$/ && node =~ /^#{graph_prefix}:/
            else
              node = target_class
            end
            out += %(
            #{graph_prefix}:#{klass}Shape
    a               #{shacl_prefix}:NodeShape ;
    #{shacl_prefix}:description "#{description&.gsub('"', "'")&.gsub(/\n|\r/, '')}" ;
    #{shacl_prefix}:targetClass  #{target_class} ;#{"\n    #{shacl_prefix}:node         #{node} ;" unless node.nil? || node.empty?}
            #{shacl_prefix}:name         "#{label}" ;
)

            if g.sheets.key?(klass.to_s)
              shape_data = g.sheets[klass.to_s]

              # add ID if not present
              #               unless shape_data.to_a.map{|m| m['name']}.include?('id')
              #                 out += %(
              #     #{shacl_prefix}:property [#{shacl_prefix}:path #{graph_prefix}:id ;
              #                  #{shacl_prefix}:name "id";
              #                  #{shacl_prefix}:description "uuid" ;
              #                  #{shacl_prefix}:datatype xsd:string ;
              #                  #{shacl_prefix}:minCount 1 ;
              #                  #{shacl_prefix}:maxCount 1 ;
              #     ] ;
              # )
              # end

              shape_data.each do |property|
                attribute = property['name'].strip
                next if attribute.empty?

                description = property['description']&.gsub('"', "'")&.gsub(/\n|\r/, '').strip
                path = "#{graph_prefix}:#{attribute}"
                datatype = property['datatype'].strip
                min_count = property['min'].strip
                max_count = property['max'].strip

                if datatype =~ /^#{graph_prefix}:/ || datatype =~ /^<#{graph_name}/
                  out += %(
                  #{shacl_prefix}:property [#{shacl_prefix}:path #{datatype} ;
                 #{shacl_prefix}:name "#{attribute}" ;
                 #{shacl_prefix}:description "#{description}" ;
                 #{shacl_prefix}:nodeKind #{shacl_prefix}:IRI ;
                 #{shacl_prefix}:class    #{datatype} ;#{min_count =~ /\d+/ ? "\n                 #{shacl_prefix}:minCount #{min_count} ;" : ''}#{max_count =~ /\d+/ ? "\n                 #{shacl_prefix}:maxCount #{max_count} ;" : ''}
    ] ;
)
                else
                  out += %(
                  #{shacl_prefix}:property [#{shacl_prefix}:path #{path} ;
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

          out
        end

        def build_schema(g, graph_prefix, graph_name)
          format = :ttl
          classes = {}
          datatype_properties = {}
          object_properties = {}

          g.shapes.each do |shape_name, metadata|
            puts shape_name
            build_classes(classes, metadata, shape_name)

            if g.sheets.key?(shape_name.to_s)
              shape_data = g.sheets[shape_name.to_s]
              shape_data.each do |property|
                attribute = property['name'].strip
                description = property['description']
                path = "#{graph_name}#{attribute}"
                datatype = property['datatype']

                data = datatype_properties[attribute] || {}
                domain = data[:domain] || []
                domain << "#{graph_name}#{shape_name.to_s}"
                datatype_properties[attribute] = {
                  domain: domain,
                  comment: description,
                  label: "#{attribute.to_s}",
                  range: datatype,
                  type: 'rdf:Property'
                }

                datatype_properties[attribute]['owl:sameAs'] = property['sameas'] unless property['sameas'].empty?

                subclass_data = classes[shape_name][:subClassOf] || []
                unless property['min'].empty?
                  subclass_data << RDF::Vocabulary.term(type: "owl:Restriction",
                                                        onProperty: path,
                                                        minCardinality: property['min'])
                end
                unless property['max'].empty?
                  subclass_data << RDF::Vocabulary.term(type: "owl:Restriction",
                                                        onProperty: path,
                                                        maxCardinality: property['max'])
                end
                classes[shape_name][:subClassOf] = subclass_data
                # end
              end
            end

            # classes.select{|k,v| v.keys.include?('owl:sameAs')}.each do |k, v|
            #   next if k.empty?
            #   sameas_data = []
            #   v['owl:sameAs'].each do |t|
            #     if t.is_a?(RDF::Vocabulary::Term)
            #       sameas_data << t
            #     else
            #       sameas_data << RDF::Vocabulary.term(type: "owl:sameAs", onProperty: "#{graph_prefix}:#{t}")
            #     end
            #   end
            #   classes[k]['owl:sameAs'] = sameas_data
            # end
          end

          lp = RDF::StrictVocabulary(graph_name)
          o = ::Class.new(lp) do
            ontology(graph_name.to_sym, {
              "dc11:title": g.ontology_metadata[:title].freeze,
              "dc11:description": g.ontology_metadata[:description].freeze,
              "dc11:date": "#{Time.now.to_s}".freeze,
              "dc11:creator": g.ontology_metadata[:author].freeze,
              "owl:versionInfo": g.ontology_metadata[:version].freeze,
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

          g.shapes.select { |k, v| !v[:same_as].empty? }.each do |k, v|
            prefix, verb = v[:same_as].split(':')
            rdf_vocabulary = RDF::Vocabulary.from_sym(prefix.upcase)
            rdf_verb = rdf_vocabulary[verb.to_sym]
            graph << RDF::Statement.new(rdf_verb, RDF::RDFV.type, RDF::OWL.Class)
            graph << RDF::Statement.new(rdf_verb, RDF::Vocab::OWL.sameAs, o[k.to_sym])
          end

          graph << o.to_enum

          graph.dump(format, prefixes: all_prefixes)
        end

        def build_plantuml(g, graph_prefix, graph_name)
          out = %(
@startuml
skinparam classFontSize 14
!define LIGHTORANGE
skinparam groupInheritance 1
skinparam componentStyle uml2
skinparam wrapMessageWidth 100
skinparam ArrowColor #Maroon

title #{g.ontology_metadata[:titel]} - #{g.ontology_metadata[:versie]} - #{Time.now.to_s}
          )

          #out += all_prefixes(false).map{|k,v| "package #{k}"}.join("\n")
          out += "\npackage #{graph_prefix} {\n"

          g.shapes.each do |shape_name, metadata|
            shape_data = g.sheets[shape_name.to_s]
            out += "class #{shape_name}"
            if shape_data && !shape_data.nil?
              if shape_data.count > 0
                out += "{\n"
                relations = []
                shape_data.each do |property|
                  attribute = property['name'].strip
                  datatype = property['datatype']
                  min_max = {}
                  ['min', 'max'].each do |n|
                    if property.key?(n) && property[n].to_i > 0
                      min_max[n] = "\"#{property[n]}\""
                    elsif property.key?(n) && property[n].eql?('*')
                      min_max[n] = '"many"'
                    end
                  end

                  out += "{field} #{datatype} : #{attribute}\n"
                  if datatype.split(':').first.eql?(graph_prefix.to_s)
                    relations << "#{datatype.split(':').last} - #{min_max.key?('max') ? min_max['max'] : ''} #{shape_name} : #{attribute} >"
                  end
                end
                out += "}\n"
                out += relations.join("\n")
              end

            end
            out += "\n"

            out += "#{shape_name} --|> #{metadata[:target_class].split(':').last}\n" unless metadata[:target_class].empty?
          end

          out += "}\n"

          out += %(
hide circle
hide methods
hide empty members
@enduml
          )

          out
        end

        def build_inflections(g)
          inflections = {}
          g.sheets['_SHAPES'].each do |row|
            inflections[row['name'].underscore.to_sym] = row['nameplural'].underscore
          end

          inflections.to_json
        end

        def parse_property(property)
          description = property['description']&.gsub('"', "'")&.gsub(/\n|\r/, '').strip
          path = "#{graph_prefix}:#{attribute}"
          datatype = property['datatype'].strip
          min_count = property['min'].strip
          max_count = property['max'].strip

          {
            description: description,
            path: path,
            datatype: datatype,
            min_count: min_count,
            max_count: max_count
          }
        end

      end
    end
  end
end
