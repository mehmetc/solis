
require 'sparql'

require_relative 'common'


module Solis
  class Store

    module RDFOperationsRunner
      # Expects:
      # - @client_sparql
      # - @logger

      def run_operations(ids_op='all')
        ops_read = []
        ops_write = []
        indexes = []
        @ops.each_with_index do |op, index|
          if ids_op.is_a?(Array)
            next unless ids_op.include?(op['id'])
          end
          if op['type'].eql?('read')
            ops_read << op
          else
            ops_write << op
          end
          indexes << index
        end
        res = {}
        # There must be guaranteed that in the following functions call
        # all exceptions are handled internally, and return in the results.
        # This way, @ops can be updated successfully.
        res.merge!(run_write_operations(ops_write))
        res.merge!(run_read_operations(ops_read))
        # remove performed operations from list;
        # following does not seem thread-safe, but ok for the now ...
        indexes.sort.reverse_each { |index| @ops.delete_at(index) }
        res
      end

      private

      def parse_json_value_from_datatype(str_value, datatype)
        case datatype
        when /http:\/\/www.w3.org\/2001\/XMLSchema#integer/,
          /http:\/\/www.w3.org\/2001\/XMLSchema#int/
          v = str_value.to_i
        when /http:\/\/www.w3.org\/2001\/XMLSchema#boolean/
          v = str_value == "true"
        when /http:\/\/www.w3.org\/2001\/XMLSchema#float/,
          /http:\/\/www.w3.org\/2001\/XMLSchema#double/
          v = str_value.to_f
        else
          v = str_value
        end
        v
      end

      def get_data_for_subject(s, context, deep)
        # create graph of query results
        graph = RDF::Graph.new
        fill_graph_from_subject_root = lambda do |g, s, deep|
          query = @client_sparql.select.where([s, :p, :o])
          query.each_solution do |solution|
            @logger.debug([s, solution.p, solution.o])
            g << [s, solution.p, solution.o]
            if deep
              # if solution.o.is_a?(RDF::URI) or solution.o.is_a?(RDF::Literal::AnyURI)
              if solution.o.is_a?(RDF::URI)
                fill_graph_from_subject_root.call(g, RDF::URI(solution.o), deep)
              end
            end
          end
        end
        fill_graph_from_subject_root.call(graph, s, deep)
        # turn graph into JSON-LD hash
        jsonld = JSON::LD::API.fromRDF(graph)
        @logger.debug(JSON.pretty_generate(jsonld))
        # compact @type
        jsonld_compacted = jsonld.map do |obj|
          Solis::Utils::JSONLD.compact_type(obj)
        end
        # adjust some sub-fields;
        # turning {"@type": "http://www.w3.org/2001/XMLSchema#anyURI", "@value": "<uri>"}
        # into {"@id": "<uri>"} is necessary for the correct framing just later;
        # having a reference in format
        # {"@type": "http://www.w3.org/2001/XMLSchema#anyURI", "@value": "<uri>"}
        # is caused by it in case it is stored as literal with datatype
        # "http://www.w3.org/2001/XMLSchema#anyURI"
        # jsonld_compacted.map! do |obj|
        #   Solis::Utils::JSONLD.anyuris_to_uris(obj)
        # end
        @logger.debug(JSON.pretty_generate(jsonld_compacted))
        f_conv = method(:parse_json_value_from_datatype)
        # compact also the values
        jsonld_compacted.map! do |obj|
          Solis::Utils::JSONLD.compact_values(obj, f_conv)
        end
        @logger.debug(JSON.pretty_generate(jsonld_compacted))
        # find the type of the (root) object with URI "s"
        obj_root = jsonld_compacted.find { |e| e['@id'] == s.to_s }
        type = obj_root.nil? ? nil : obj_root['@type']
        # frame JSON-LD; this will:
        # - compact attributes thanks to "@vocab"
        # - embed (at any depth) objects to the root one, thanks to @embed;
        # this needs references in {"@id": "<uri>"} format (see above)
        # - avoid having other objects but the root one, thanks to "@type" filter
        frame = JSON.parse %(
          {
            "@context": #{context.to_json},
            "@type": "#{type}",
            "@embed": "@always"
          }
        )
        jsonld_compacted_framed = JSON::LD::API.frame(jsonld_compacted, frame)
        @logger.debug(JSON.pretty_generate(jsonld_compacted_framed))
        # produce result
        res = {}
        # if framing created a "@graph" (empty) attribute,
        # then there was no matching result in the framing
        unless jsonld_compacted_framed.key?('@graph')
          res = jsonld_compacted_framed
        end
        context = res.delete('@context')
        # puts JSON.pretty_generate(res)
        # if res.empty?
        #   raise StandardError, "no entity with id '#{s.to_s}'"
        # end
        [res, context]
      end

      def ask_if_object_is_referenced(o)
        # to make this more robust, the for object that are:
        # - URI (within triangular braces, like <uri>)
        # - a literal of type http://www.w3.org/2001/XMLSchema#anyURI
        result = @client_sparql.ask.whether([:s, :p, o]).true?
        o_literal = RDF::Literal.new(o.to_s, datatype: 'http://www.w3.org/2001/XMLSchema#anyURI')
        result_literal = @client_sparql.ask.whether([:s, :p, o_literal]).true?
        result or result_literal
      end

      def ask_if_subject_exists(s)
        result = @client_sparql.ask.whether([s, :p, :o]).true?
        result
      end

      def run_read_operations(ops_generic)
        res = ops_generic.map do |op|
          case op['name']
          when 'get_data_for_id'
            id = op['content'][0]
            context = op['content'][1]
            deep = op['opts'] == Solis::Store::GetMode::DEEP
            s = RDF::URI(id)
            r = get_data_for_subject(s, context, deep)
          when 'ask_if_id_is_referenced'
            id = op['content'][0]
            o = RDF::URI(id)
            r = ask_if_object_is_referenced(o)
          when 'ask_if_id_exists'
            id = op['content'][0]
            s = RDF::URI(id)
            r = ask_if_subject_exists(s)
          end
          [op['id'], r]
        end.to_h
        res
      end

      def run_write_operations(ops)
        ops_save = []
        ops_destroy = []
        ops.each do |op|
          if op['name'].eql?('delete_attributes_for_id')
            ops_destroy << op
          else
            ops_save << op
          end
        end
        res = {}
        res.merge!(run_save_operations(ops_save))
        res.merge!(run_destroy_operations(ops_destroy))
        res
      end

      def run_destroy_operations(ops_generic)
        ss = []
        ops_generic.map do |op|
          case op['name']
          when 'delete_attributes_for_id'
            id = op['content'][0]
            s = RDF::URI(id)
            ss << s
          end
        end
        r = delete_attributes_for_subjects(ss)
        res = {}
        ops_generic.each do |op|
          res[op['id']] = r
        end
        res
      end

      def delete_attributes_for_subjects(ss)
        unless ss.empty?
          str_ids = ss.map { |s| "<#{s.to_s}>" } .join(' ')
          # This query string takes care of:
          # - deleting attributes of one of more subjects
          # - checking that those subjects are not objects in other triples
          # (i.e. they are not referenced)
          # Both together in the same query.
          str_query = %(
            DELETE {
              ?s ?p ?o
            }
            WHERE {
              FILTER NOT EXISTS { ?s_ref ?p_ref ?s } .
              VALUES ?s { #{str_ids} } .
              ?s ?p ?o .
            }
          )
          @logger.debug("\n\nDELETE QUERY:\n\n")
          @logger.debug(str_query)
          @logger.debug("\n\n")
          # run query
          # TODO: repository seems a snapshot of the triple store
          # after the query.
          # This seems inefficient, especially if the store contains
          # a lot of triple. To check better ...
          repository = @client_sparql.query(str_query, update: true)
          # check if delete failed because subjects were referenced
          client_sparql = SPARQL::Client.new(repository)
          subjects_were_referenced = client_sparql.ask
                                                  .where([:s_ref, :p_ref, :s])
                                                  .values(:s, *ss)
                                                  .true?
          # if subjects_were_referenced
          #   raise StandardError, "any of these '#{str_ids}' was referenced"
          # end
          success = !subjects_were_referenced
          message = ''
          if subjects_were_referenced
            message = "any of these '#{str_ids}' was referenced"
          end
          {
            "success" => success,
            "message" => message
          }
        end
      end

      def run_save_operations(ops_generic)

        # convert endpoint-agnostic operations into RDF operations
        ops = ops_generic.map do |op|
          op_rdf = Marshal.load(Marshal.dump(op))
          case op['name']
          when 'save_id_with_type'
            id, _, type = op_rdf['content']
            s, p, o = [RDF::URI(id), RDF::RDFV.type, type]
            op_rdf['content'] = [s, p, o]
          when 'save_attribute_for_id'
            id, name_attr, val_attr, type_attr = op_rdf['content']
            s, p, o = prepare_statement(id, name_attr, val_attr, type_attr)
            op_rdf['content'] = [s, p, o]
          when 'delete_attribute_for_id'
            id, name_attr = op_rdf['content']
            s, p = prepare_subject_and_predicate(id, name_attr)
            op_rdf['content'] = [s, p]
          end
          op_rdf
        end

        # create empty delete graph
        insert = {
          'graph' => RDF::Graph.new
        }

        # create empty insert graph
        delete = {
          'graph' => RDF::Graph.new
        }

        # create an operations cache:
        # group operations by subject and predicate.
        # it can be useful later.
        cache_ops = {}
        ops.each do |op|
          st = op['content']
          key_sp = "#{st[0].to_s}_#{st[1].to_s}"
          cache_ops[key_sp] = [] unless cache_ops.key?(key_sp)
          cache_ops[key_sp] << st[2]
        end

        # begin critical section
        @logger.debug("\n\n-- BEGIN CRITICAL SECTION: \n\n")

        # write graphs
        ops.each do |op|

          case op['opts']

          when Solis::Store::SaveMode::PRE_DELETE_PEERS
            st = op['content']
            objects = get_objects_for_subject_and_predicate(st[0], st[1])
            if objects.empty?
              # attribute is not present; add it
              insert['graph'] << st
            else
              # pre-delete peer attributes, don't care about what exists;
              objects.each do |o|
                delete['graph'] << [st[0], st[1], o]
              end
              # add new attribute values
              insert['graph'] << st
            end

          when Solis::Store::SaveMode::PRE_DELETE_PEERS_IF_DIFF_SET
            st = op['content']
            objects = get_objects_for_subject_and_predicate(st[0], st[1])
            if objects.empty?
              # attribute is not present; add it
              insert['graph'] << st
            else
              key_sp = "#{st[0].to_s}_#{st[1].to_s}"
              if objects.sort != cache_ops[key_sp].sort
                # attribute is present but with different values that the ones to write;
                # stage those old ones for deletion
                objects.each do |o|
                  delete['graph'] << [st[0], st[1], o]
                end
                # add new attribute values
                insert['graph'] << st
              end
            end

          when Solis::Store::SaveMode::APPEND_IF_NOT_PRESENT
            st = op['content']
            objects = get_objects_for_subject_and_predicate(st[0], st[1])
            if objects.empty?
              # attribute is not present; add it
              insert['graph'] << st
            else
              unless objects.include?(st[2])
                # peer attributes exist, but not with this value;
                # stage those old ones for deletion
                objects.each do |o|
                  delete['graph'] << [st[0], st[1], o]
                end
                # add new attribute values
                insert['graph'] << st
              end
            end

          when Solis::Store::DeleteMode::DELETE_ATTRIBUTE
            st = op['content']
            objects = get_objects_for_subject_and_predicate(st[0], st[1])
            # delete peer attributes;
            objects.each do |o|
              delete['graph'] << [st[0], st[1], o]
            end

          end


        end


        unless delete['graph'].empty? and insert['graph'].empty?

          method = 2

          case method
          when 1

            rollbacks = []

            # run delete query
            str_query = SPARQL::Client::Update::DeleteData.new(delete['graph'], graph: @name_graph).to_s
            @logger.debug("\n\nDELETE QUERY:\n\n")
            @logger.debug(str_query)
            @logger.debug("\n\n")
            begin
              @client_sparql.delete_data(delete['graph'])
            rescue RuntimeError => e
              @logger.debug("error deleting data: #{e.full_message}")
              @logger.debug("rolling back ...")
              rollback(rollbacks)
              raise RuntimeError, e
            end
            rollbacks << {
              type: 'query_insert',
              graph: delete['graph']
            }

            # run insert query
            str_query = SPARQL::Client::Update::InsertData.new(insert['graph'], graph: @name_graph).to_s
            @logger.debug("\n\nINSERT QUERY:\n\n")
            @logger.debug(str_query)
            @logger.debug("\n\n")
            begin
              @client_sparql.insert_data(insert['graph'])
            rescue RuntimeError => e
              @logger.debug("error inserting data: #{e.full_message}")
              @logger.debug("rolling back ...")
              rollback(rollbacks)
              raise RuntimeError, e
            end
            rollbacks << {
              type: 'query_delete',
              graph: insert['graph']
            }

          when 2

            # Found out later that the following is possible by SPARQL language.
            # Of course better than method 1 because supposedly atomic (no rollout strategies needed).

            str_query = SPARQL::Client::Update::DeleteInsert.new(delete['graph'], insert['graph'], nil, graph: @name_graph).to_s
            @logger.debug("\n\nDELETE/INSERT QUERY:\n\n")
            @logger.debug(str_query)
            @logger.debug("\n\n")

            method_di = 1

            case method_di
            when 1
              # this works

              @client_sparql.delete_insert(delete['graph'], insert['graph'], nil)
            when 2
              # this does not, which is strange because the DELETE/WHERE query works
              # when using @client_sparql.query(str_query, update: true).
              # It would be nice to have it running so we can use the raw SPARQL query string
              # and be sure it is not internally split into DELETE + INSERT.

              # str_query = "WITH <#{@name_graph}>"
              # unless delete['graph'].empty?
              #   str_query += "\nDELETE {\n#{delete['graph'].dump(:ntriples)}}"
              # end
              # unless insert['graph'].empty?
              #   str_query += "\nINSERT {\n#{insert['graph'].dump(:ntriples)}}"
              # end
              # # str_query += "\nWHERE { }\n"
              # # str_query += "\nWHERE { ?s ?p ?o }\n"
              # puts str_query

              @client_sparql.query(str_query, update: true)
              # @client_sparql.instance_variable_set("@op", :update)
              # puts @client_sparql.instance_variable_get("@op")
              # SPARQL.execute(str_query, @client_sparql.url, update: true)
            end

          end

        end

        # end critical section
        @logger.debug("\n\n-- END CRITICAL SECTION: \n\n")

        res = ops_generic.map do |op|
          [op['id'], 'ok']
        end.to_h
        res

      end

      def prepare_subject_and_predicate(id, name_attr)
        s = RDF::URI(id)
        p = RDF::URI(name_attr)
        [s, p]
      end

      def prepare_statement(id, name_attr, val_attr, type_attr)
        s, p = prepare_subject_and_predicate(id, name_attr)
        if type_attr.eql?('URI')
          o = RDF::URI(val_attr)
        else
          type_attr_known = RDF::Vocabulary.find_term(type_attr)
          type_attr = type_attr_known unless type_attr_known.nil?
          o = RDF::Literal.new(val_attr, datatype: type_attr)
        end
        [s, p, o]
      end

      def get_objects_for_subject_and_predicate(s, p)
        objects = []
        result = @client_sparql.select.where([s, p, :o])
        result.each_solution do |solution|
          objects << solution.o
        end
        @logger.debug("GET_OBJECTS_FOR_SUBJECT_AND_PREDICATE: #{s}, #{p}:\n#{objects}")
        objects
      end

      def rollback(rollbacks)
        rollbacks.each_with_index do |op, i|
          @logger.debug("\n\nROLLBACK QUERY: #{i+1}")
          case op[:type]
          when 'query_insert'
            str_query = SPARQL::Client::Update::InsertData.new(op[:graph], graph: @name_graph).to_s
            @logger.debug("\n\nINSERT QUERY (AS ROLLBACK QUERY):\n\n")
            @logger.debug(str_query)
            @logger.debug("\n\n")
            @client_sparql.insert_data(op[:graph])
          when 'query_delete'
            str_query = SPARQL::Client::Update::DeleteData.new(op[:graph], graph: @name_graph).to_s
            @logger.debug("\n\nDELETE QUERY (AS ROLLBACK QUERY):\n\n")
            @logger.debug(str_query)
            @logger.debug("\n\n")
            @client_sparql.delete_data(op[:graph])
          end
        end
      end

    end

  end
end