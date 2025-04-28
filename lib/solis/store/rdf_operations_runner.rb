
require 'sparql'

require_relative 'common'


module Solis
  class Store

    module RDFOperationsRunner
      # Expects:
      # - @client_sparql

      def run_operations_as_rdf(ops_generic)

        # convert endpoint-agnostic operations into RDF operations
        ops = ops_generic.map do |op|
          op_rdf = Marshal.load(Marshal.dump(op))
          case op['type']
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
        puts "\n\n-- BEGIN CRITICAL SECTION: \n\n"

        # write graphs
        ops.each do |op|

          case op['mode']

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

        rollbacks = []

        # run delete query
        str_query = SPARQL::Client::Update::DeleteData.new(delete['graph'], graph: @name_graph).to_s
        puts "\n\nDELETE QUERY:\n\n"
        puts str_query
        puts "\n\n"
        begin
          @client_sparql.delete_data(delete['graph'])
        rescue RuntimeError => e
          puts "error deleting data: #{e.full_message}"
          puts "rolling back ..."
          rollback(rollbacks)
          raise RuntimeError, e
        end
        rollbacks << {
          type: 'query_insert',
          graph: delete['graph']
        }

        # run insert query
        str_query = SPARQL::Client::Update::InsertData.new(insert['graph'], graph: @name_graph).to_s
        puts "\n\nINSERT QUERY:\n\n"
        puts str_query
        puts "\n\n"
        begin
          @client_sparql.insert_data(insert['graph'])
        rescue RuntimeError => e
          puts "error inserting data: #{e.full_message}"
          puts "rolling back ..."
          rollback(rollbacks)
          raise RuntimeError, e
        end
        rollbacks << {
          type: 'query_delete',
          graph: insert['graph']
        }

        # end critical section
        puts "\n\n-- END CRITICAL SECTION: \n\n"

      end

      def prepare_subject_and_predicate(id, name_attr)
        s = RDF::URI(id)
        p = RDF::URI(name_attr)
        [s, p]
      end

      def prepare_statement(id, name_attr, val_attr, type_attr)
        s, p = prepare_subject_and_predicate(id, name_attr)
        if type_attr.eql?('http://www.w3.org/2006/time#DateTimeInterval')
          o = RDF::Literal.new(ISO8601::TimeInterval.parse(val_attr).to_s, datatype: type_attr)
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
        puts "GET_OBJECTS_FOR_SUBJECT_AND_PREDICATE: #{s}, #{p}:\n#{objects}"
        objects
      end

      private

      def rollback(rollbacks)
        rollbacks.each_with_index do |op, i|
          puts "\n\nROLLBACK QUERY: #{i+1}"
          case op[:type]
          when 'query_insert'
            str_query = SPARQL::Client::Update::InsertData.new(op[:graph], graph: @name_graph).to_s
            puts "\n\nINSERT QUERY (AS ROLLBACK QUERY):\n\n"
            puts str_query
            puts "\n\n"
            @client_sparql.insert_data(op[:graph])
          when 'query_delete'
            str_query = SPARQL::Client::Update::DeleteData.new(op[:graph], graph: @name_graph).to_s
            puts "\n\nDELETE QUERY (AS ROLLBACK QUERY):\n\n"
            puts str_query
            puts "\n\n"
            @client_sparql.delete_data(op[:graph])
          end
        end
      end

    end

  end
end