module Solis
    module QueryFilter
      def filter(params)
        parsed_filters = {values: ["VALUES ?type {#{target_class}}"], concepts: ['?concept a ?type .'] }
        if params.key?(:filters)
          filters = params[:filters]

          if filters.is_a?(String)
            parsed_filters[:concepts] << concept_by_string(filters)
          else
            i=0
            filters.each do |key, value|
              if is_key_a_shacl_entity?(key) #nodeKind sh:URI
                parsed_filters[:values] << values_for(key, value)
                parsed_filters[:concepts] << concepts_for(key)
              else
                parsed_filters[:concepts] << other_stuff(key, value, i)
              end
              i+=1
            end
          end
        end

        @filter = parsed_filters
        self
      rescue StandardError => e
        LOGGER.error(e.message)
        LOGGER.error(e.backtrace.join("\n"))
        raise Error::GeneralError, e.message
      end

      private

      def is_key_a_shacl_entity?(key)
        @metadata[:attributes].key?(key.to_s) && @metadata[:attributes][key.to_s][:node_kind] && @metadata[:attributes][key.to_s][:node_kind]&.vocab == RDF::Vocab::SH
      end

      def values_for(key, value)
        values_model = @model.class.graph.shape_as_model(@metadata[:attributes][key.to_s][:datatype].to_s)&.new
        "VALUES ?filter_by_#{key}_id{#{value.split(',').map {|v| target_class_by_model(values_model, v)}.join(' ')}}" if values_model
      end

      def concepts_for(key)
        filter_predicate = URI.parse(@metadata[:attributes][key.to_s][:path])
        filter_predicate.path = "/#{key.to_s.downcase}"

        "?concept <#{filter_predicate.to_s}> ?filter_by_#{key}_id ."
      end

      def concept_by_string(filters)
        contains = filters.split(',').map { |m| "CONTAINS(LCASE(str(?__search)), LCASE(\"#{m}\"))" }.join(' || ')
        "?concept (#{@metadata[:attributes].map { |_, m| "(<#{m[:path]}>)" }.join('|')}) ?__search FILTER CONTAINS(LCASE(str(?__search)), LCASE(\"#{contains}\")) ."
      end

      def other_stuff(key, value, i)
        filter = ''
        unless value.is_a?(Hash) && value.key?(:value)
          #TODO: only handles 'eq' for now
          value = { value: value.first, operator: '=', is_not: false }
        end

        if value[:value].is_a?(String)
          contains = value[:value].split(',').map { |m| "CONTAINS(LCASE(str(?__search#{i})), LCASE(\"#{m}\"))" }.join(' || ')
        else
          value[:value] = [value[:value]] unless value[:value].is_a?(Array)
          value[:value].flatten!
          contains = value[:value].map { |m| "CONTAINS(LCASE(str(?__search#{i})), LCASE(\"#{m}\"))" }.join(' || ')
        end

        metadata = @metadata[:attributes][key.to_s]
        if metadata
          if metadata[:path] =~ %r{/id$}
            if value[:value].is_a?(String)
              contains = value[:value].split(',').map { |m| "\"#{m}\"" }.join(',')
            else
              value[:value].flatten!
              contains = value[:value].map { |m| "\"#{m}\"" }.join(',')
            end
            if value[:is_not]
              value[:value].each do |v|
                filter = "filter( !exists {?concept <#{@model.class.graph_name}id> \"#{v}\"})"
              end
            else
              filter = "?concept <#{@model.class.graph_name}id> ?__search FILTER (?__search IN(#{contains})) .\n"
            end
          else
            datatype = ''
            datatype = "^^<http://www.w3.org/2001/XMLSchema#boolean>" if metadata[:datatype].eql?(:boolean)

            if ["=", "<", ">"].include?(value[:operator])
              not_operator = value[:is_not] ? '!' : ''
              value[:value].each do |v|
                filter = "?concept <#{metadata[:path]}> ?__search#{i} FILTER(?__search#{i} #{not_operator}#{value[:operator]} \"#{v}\"#{datatype}) .\n"

                if metadata[:datatype_rdf].eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#langString')
                    filter  = "?concept <#{metadata[:path]}> ?__search#{i} "
                    filter += "FILTER(langMatches( lang(?__search#{i}), \"*\" )). "
                    filter += "FILTER(str(?__search#{i}) #{not_operator}#{value[:operator]} \"#{v}\"#{datatype}) .\n"
                end


              end
            else
              filter = "?concept <#{metadata[:path]}> ?__search#{i} FILTER(#{contains.empty? ? '""' : contains}) .\n"
            end
          end
        end

        filter
      end

    end
end