module Solis
    module QueryFilter
      def filter(params)
        if params.key?(:language)
          @language = params[:language].nil? || params[:language].blank? ? nil : params[:language]
        end

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

      def values_for(key, value, i=0)
        values_model = @model.class.graph.shape_as_model(@metadata[:attributes][key.to_s][:datatype].to_s)&.new
        if value.is_a?(Hash)
          other_stuff(key, value, i)
        else
          "VALUES ?filter_by_#{key}_id{#{value.split(',').map {|v| target_class_by_model(values_model, v)}.join(' ')}}" if values_model
        end
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
          value = { value: value.is_a?(Array) ? value.first : value, operator: '=', is_not: false }
        end

        if value[:value].is_a?(String)
          contains = value[:value].split(',').map { |m| "CONTAINS(LCASE(str(?__search#{i})), LCASE(\"#{m}\"))" }.join(' || ')
        else
          value[:value] = [value[:value]] unless value[:value].is_a?(Array)
          value[:value].flatten!
          contains = value[:value].map { |m| m.is_a?(String) ? "CONTAINS(LCASE(str(?__search#{i})), LCASE(\"#{m}\"))" : next }.join(' || ')
        end

        # Ensure value[:value] is always an array for consistent handling below
        value[:value] = [value[:value]] unless value[:value].is_a?(Array)
        value[:value].flatten!

        metadata = @metadata[:attributes][key.to_s]
        if metadata
          if metadata[:path] =~ %r{/id$}
            # value[:value] is guaranteed to be an array at this point
            contains = value[:value].map { |m| "\"#{m}\"" }.join(',')
            if value[:is_not]
              value[:value].each do |v|
                v=normalize_string(v)
                filter = "filter( !exists {?concept <#{@model.class.graph_name}id> \"#{v}\"})"
              end
            else
              filter = "?concept <#{@model.class.graph_name}id> ?__search FILTER (?__search IN(#{contains})) .\n"
            end
          else
            datatype = ''
            case metadata[:datatype]
            when :boolean
              datatype = "^^<http://www.w3.org/2001/XMLSchema#boolean>"
            when :integer
              datatype = "^^<http://www.w3.org/2001/XMLSchema#integer>"
            when :float, :double
              datatype = "^^<http://www.w3.org/2001/XMLSchema#double>"
            when :date
              datatype = "^^<http://www.w3.org/2001/XMLSchema#date>"
            when :datetime, :time
              datatype = "^^<http://www.w3.org/2001/XMLSchema#dateTime>"
            when :anyuri
              datatype = "^^<http://www.w3.org/2001/XMLSchema#anyURI>"
            end

            if ["=", "<", ">", ">=", "<="].include?(value[:operator])
              not_operator = value[:is_not] ? '!' : ''
              value[:value].each do |v|
                if metadata[:datatype_rdf].eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#langString')
                    filter  = "?concept <#{metadata[:path]}> ?__search#{i} "
                    if v.is_a?(Hash)
                      filter += "FILTER(langMatches( lang(?__search#{i}), \"#{v[:"@language"]}\" )). "
                      search_for = v[:"@value"].is_a?(Array) ? v[:"@value"].first : v[:"@value"]
                    else
                      search_for = v
                    end

                    search_for = normalize_string(search_for)
                    filter += "FILTER(str(?__search#{i}) #{not_operator}#{value[:operator]} \"#{search_for}\"#{datatype}) .\n"
                elsif (metadata[:datatype_rdf].eql?('http://www.w3.org/2001/XMLSchema#anyURI') || !metadata[:node].nil?) && ["=", "!="].include?(value[:operator])
                  # Special handling for anyURI references to other entities (only for equality/inequality)
                  model_graph_name = Solis::Options.instance.get.key?(:graphs) ? Solis::Options.instance.get[:graphs].select{|s| s['type'].eql?(:main)}&.first['name'] : @model.class.graph_name
                  if value[:is_not]
                    #filter = "filter( !exists {?concept <#{metadata[:path]}> ?__search#{i} . ?__search#{i} <#{model_graph_name}id> \"#{v}\"})"
                    filter = "filter( !exists {?concept <#{metadata[:path]}> <#{v}>})"
                  else
                    #filter = "?concept <#{metadata[:path]}> ?__search#{i} . ?__search#{i} <#{model_graph_name}id> ?__search#{i}_#{i} filter(?__search#{i}_#{i} = \"#{v}\")."
                    filter = "?concept <#{metadata[:path]}> <#{v}>."
                  end
                else
                  v=normalize_string(v)
                  filter = "?concept <#{metadata[:path]}> ?__search#{i} FILTER(?__search#{i} #{not_operator}#{value[:operator]} \"#{v}\"#{datatype}) .\n"
                end
              end
            else # if "~" contains
              if metadata[:datatype_rdf].eql?( 'http://www.w3.org/2001/XMLSchema#anyURI') || !metadata[:node].nil?
                model_graph_name = Solis::Options.instance.get.key?(:graphs) ? Solis::Options.instance.get[:graphs].select{|s| s['type'].eql?(:data)}&.first['name'] : @model.class.graph_name
                filter = "?concept <#{metadata[:path]}> ?__search#{i} . ?__search#{i} <#{model_graph_name}id> ?__search#{i}_#{i} filter(?__search#{i}_#{i} = \"#{value[:value].first}\")."
              else
                filter = "?concept <#{metadata[:path]}> ?__search#{i} FILTER(#{contains.empty? ? '""' : contains}) .\n"
              end
            end
          end
        end

        filter
      end

      def normalize_string(string)
        if string.is_a?(String)
          string.gsub(/\t/, '\t').gsub(/\n/,'\n').gsub(/\r/,'\r').gsub(/\f/,'\f').gsub(/"/,'\"').gsub(/'/,'\'').gsub(/\\/,'\\')
        else
          string
        end
      end

    end
end