
require 'sparql'

require_relative 'common'


module Solis
  class Store

    module RDFOperationsRunner

      # Expects:
      # - @client_sparql
      # - @logger
      # - @mutex_repository

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
        message = ""
        success = true
        # if framing created a "@graph" (empty) attribute,
        # then there was either no matching result in the framing,
        # or embedded objects with the same type (only first matters)
        if jsonld_compacted_framed.key?('@graph')
          if jsonld_compacted_framed['@graph'].size == 0
            message = "no entity with id '#{s.to_s}'"
            success = false
          else
            res = jsonld_compacted_framed['@graph'][0]
            res.merge!(jsonld_compacted_framed['@context'])
          end
        else
          res = jsonld_compacted_framed
        end
        context = res.delete('@context')
        {
          "success" => success,
          "message" => message,
          "data" => {
            "obj" => res,
            "context" => context
          }
        }
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
#         unless ss.empty?
#           str_ids = ss.map { |s| "<#{s.to_s}>" }.join(' ')
#
#           # Fixed single query: only delete if subjects are NOT referenced
#           str_query = %(
# WITH <#{@client_sparql.options[:graph]}>
#   DELETE {
#     ?s ?p ?o
#   }
#   WHERE {
#     VALUES ?s { #{str_ids} }
#     ?s ?p ?o .
#     FILTER NOT EXISTS {
#       ?other_entity ?any_property ?s
#     }
#   }
#     )
#
#           @logger.debug("\n\nDELETE QUERY:\n\n")
#           @logger.debug(str_query)
#           @logger.debug("\n\n")
#
#           # Count subjects before deletion to check if any were actually deleted
#           count_query = %(
#       SELECT (COUNT(DISTINCT ?s) AS ?count) WHERE {
#         VALUES ?s { #{str_ids} }
#         ?s ?p ?o .
#         FILTER NOT EXISTS {
#           ?other_entity ?any_property ?s
#         }
#       }
#     )
#
#           # Check how many subjects can be safely deleted
#           count_result = @client_sparql.query(count_query)
#           deletable_count = count_result.first[:count].to_i
#
#           if deletable_count == 0
#             # Check if subjects exist but are referenced
#             exist_query = %(
#         ASK WHERE {
#           VALUES ?s { #{str_ids} }
#           ?s ?p ?o
#         }
#       )
#
#             subjects_exist = @client_sparql.ask(exist_query)
#
#             if subjects_exist
#               return {
#                 "success" => false,
#                 "message" => "Cannot delete: subjects are referenced by other entities"
#               }
#             else
#               return {
#                 "success" => true,
#                 "message" => "No subjects found to delete"
#               }
#             end
#           end
#
#           # Execute the deletion
#           begin
#             repository = @client_sparql.query(str_query, update: true)
#
#             if deletable_count < ss.length
#               return {
#                 "success" => false,
#                 "message" => "Only #{deletable_count} of #{ss.length} subjects could be deleted (others are referenced)"
#               }
#             else
#               return {
#                 "success" => true,
#                 "message" => "Successfully deleted #{deletable_count} subject(s)"
#               }
#             end
#           rescue => e
#             return {
#               "success" => false,
#               "message" => "Delete failed: #{e.message}"
#             }
#           end
#         end
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

        return {} if ops_generic.empty?

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
          else
            op_rdf = nil
          end
          op_rdf
        end.compact

        ops_filters = ops_generic.map do |op|
          op_rdf = Marshal.load(Marshal.dump(op))
          case op['name']
          when 'set_attribute_condition_for_saves'
            id, name_attr, val_attr, type_attr = op_rdf['content']
            s, p, o = prepare_statement(id, name_attr, val_attr, type_attr)
            op_rdf['row_where'] = RDF::Statement(s, p, o).to_s
          when 'set_not_existing_id_condition_for_saves'
            id = op_rdf['content'][0]
            op_rdf['row_where'] = "FILTER NOT EXISTS { <#{id}> ?p ?o }"
          else
            op_rdf = nil
          end
          op_rdf
        end.compact

        clause_where = ops_filters.map { |op| op['row_where'] } .join(' ')

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

        nothing_to_save = false

        success = true
        message = ""
        message_dirty = "data is dirty"

        unless nothing_to_save

          method = 2

          case method
          when 1

          when 2

            method_di = 3

            case method_di

            when 3

              case @client_sparql.url
              when RDF::Queryable

                perform_delete_insert_where_with_report_atomic = lambda do
                  str_query_ask = "ASK WHERE { #{clause_where} }"
                  @logger.debug("\n\nASK QUERY:\n\n")
                  @logger.debug(str_query_ask)
                  @logger.debug("\n\n")
                  has_pattern = @client_sparql.query(str_query_ask).true?
                  if has_pattern
                    str_query = create_delete_insert_where_query(delete['graph'], insert['graph'], clause_where)
                    @logger.debug("\n\nDELETE/INSERT QUERY:\n\n")
                    @logger.debug(str_query)
                    @logger.debug("\n\n")
                    @client_sparql.update(str_query)
                  end
                  report = { can_update: has_pattern }
                  report
                end
                report = nil
                if @mutex_repository.nil?
                  report = perform_delete_insert_where_with_report_atomic.call
                else
                  @mutex_repository.synchronize do
                    report = perform_delete_insert_where_with_report_atomic.call
                  end
                end
                unless report[:can_update]
                  success = false
                  message = message_dirty
                end


              else

                query = create_delete_insert_where_query(delete['graph'], insert['graph'], clause_where, name_graph=@name_graph)
                @logger.debug("\n\nDELETE/INSERT QUERY:\n\n")
                @logger.debug(query)
                @logger.debug("\n\n")
                response = client.response(query)
                report = client.parse_report(response)
                if report[:count_update] == 0
                  success = false
                  message = message_dirty
                end

              end

            end

          end

        end

        res = ops_generic.map do |op|
          [op['id'], {
            "success" => success,
            "message" => message
          }]
        end.to_h
        res

      end

      def prepare_subject(id)
        RDF::URI(id)
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

      def create_delete_insert_where_query(graph_delete, graph_insert, clause_where, name_graph=nil)
        str_query = ""
        unless name_graph.nil?
          str_query += "WITH GRAPH <#{name_graph}>"
        end
        str_query += "DELETE { #{graph_delete.dump(:ntriples)} } INSERT { #{graph_insert.dump(:ntriples)} } WHERE { #{clause_where} }"
        str_query
      end

    end

  end
end