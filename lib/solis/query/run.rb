require 'solis/store/sparql/client'
require 'solis/config_file'

class Solis::Query::Runner
  def self.run(entity, query, options = {})
    result = {}

    c = Solis::Store::Sparql::Client.new(Solis::Options.instance.get[:sparql_endpoint], graph_name: graph_name)
    r = c.query(query, options)

    if r.is_a?(SPARQL::Client)
      result = direct_transform_with_embedding(r, entity, options)
    else
      t = r.map(&:to_h)
      result = sanitize_result({'@graph' => t})
    end
    result
  rescue StandardError => e
    puts e.message
    raise e
  end

  def self.direct_transform_with_embedding(client, entity, options = {})
    results = client.query('select * where{?s ?p ?o}')

    # Step 1: Group all triples by subject
    grouped = group_by_subject(results)

    # Step 2: Build objects index (without embedding yet)
    objects_index = build_objects_index(grouped)

    # Step 3: Embed references recursively
    max_depth = options[:max_embed_depth] || 10
    root_subjects = find_root_subjects(grouped, entity)

    root_subjects.map do |subject|
      embed_references(objects_index[subject], objects_index, max_depth, Set.new)
    end.compact
  end

  private

  def self.group_by_subject(results)
    results.each_with_object({}) do |solution, acc|
      subject = solution.s.to_s
      acc[subject] ||= []
      acc[subject] << { predicate: solution.p, object: solution.o }
    end
  end

  def self.build_objects_index(grouped)
    grouped.each_with_object({}) do |(subject, triples), index|
      obj = {
        '_id' => subject,                    # Full URI for resolution
        'id' => nil,                         # Will be set from predicate if exists
        '@subject' => subject,               # Internal marker for reference resolution
        '@type' => nil
      }

      triples.each do |triple|
        predicate = triple[:predicate]
        object = triple[:object]

        # Handle rdf:type
        if (predicate.to_s !~/#{graph_name}/ && predicate.to_s =~ /type$/i) || predicate == RDF::RDFV.type
          obj['@type'] = object.to_s.split('/').last
          next
        end

        # Get predicate name (last part of URI)
        pred_name = predicate.to_s.split('/').last.underscore

        # Extract value
        value = if object.is_a?(RDF::URI)
                  { '@ref' => object.to_s } # Mark as reference for later resolution
                else
                  extract_value(object)
                end

        # Capture the 'id' predicate value specifically
        if pred_name == 'id'
          obj['id'] = value
          next
        end

        # Handle multiple values for same predicate
        if obj.key?(pred_name)
          obj[pred_name] = [obj[pred_name]] unless obj[pred_name].is_a?(Array)
          obj[pred_name] << value
        else
          obj[pred_name] = value
        end
      end

      # Fallback: if no 'id' predicate was found, extract from URI
      if obj['id'].nil?
        obj['id'] = subject.split('/').last
      end

      if obj['@type'].nil?
        obj['@type'] = subject.split('/')[-2].classify
      end

      index[subject] = obj
    end
  end

  def self.find_root_subjects(grouped, entity)
    # Find subjects that match the requested entity type
    grouped.select do |subject, triples|
      type_triple = triples.find { |t| t[:predicate].to_s =~ /type$/i || t[:predicate] == RDF::RDFV.type }
      next false unless type_triple

      type_name = type_triple[:object].to_s.split('/').last
      type_name.downcase == entity.downcase ||
        type_name.tableize == entity.tableize ||
        type_name == entity
    end.keys
  end

  def self.embed_references(obj, objects_index, max_depth, visited, current_depth = 0)
    return nil if obj.nil?

    subject = obj['@subject']

    # At max depth, return minimal reference with both IDs
    if current_depth >= max_depth
      #return { '_id' => obj['_id'], 'id' => obj['id'], '@type' => obj['@type'] }
      return { '_id' => obj['_id'], 'id' => obj['id'] }
    end

    # Circular reference detection
    if visited.include?(subject)
      # Return a reference object instead of embedding
      #return { '_id' => obj['_id'], 'id' => obj['id'], '@type' => obj['@type'] }
      return { '_id' => obj['_id'], 'id' => obj['id'] }
    end

    visited = visited.dup
    visited.add(subject)

    # Create clean copy without internal markers (except _id)
    result = {
      '_id' => obj['_id'],
      'id' => obj['id']
    }

    obj.each do |key, value|
      next if key.start_with?('@')  # Skip internal markers
      next if key == '_id' || key == 'id'  # Already added

      if obj.key?('@type') &&Solis::Options.instance.get[:solis].shape?(obj['@type'])
        entity = Solis::Options.instance.get[:solis].shape_as_model(obj['@type'])
        entity_maxcount = entity.metadata[:attributes][key][:maxcount]
      end
      resolved_value = resolve_value(value, objects_index, max_depth, visited, current_depth)
      resolved_value = [resolved_value] if (entity_maxcount.nil? || entity_maxcount > 1) && !resolved_value.is_a?(Array)

      result[key] = resolved_value
    end

    result
  end

  def self.resolve_value(value, objects_index, max_depth, visited, current_depth)
    case value
    when Array
      value.map { |v| resolve_value(v, objects_index, max_depth, visited, current_depth) }
    when Hash
      if value.key?('@ref')
        # This is a reference - try to embed it
        ref_uri = value['@ref']
        referenced_obj = objects_index[ref_uri]

        if referenced_obj
          embed_references(referenced_obj, objects_index, max_depth, visited, current_depth + 1)
        else
          # External reference - return both IDs
          { '_id' => ref_uri, 'id' => ref_uri.split('/').last }
        end
      else
        # Regular hash - recurse
        value.transform_values { |v| resolve_value(v, objects_index, max_depth, visited, current_depth) }
      end
    else
      value
    end
  end

  def self.extract_value(literal)
    return literal.to_s if literal.is_a?(RDF::URI)

    datatype = literal.datatype&.to_s

    case datatype
    when "http://www.w3.org/2001/XMLSchema#dateTime"
      DateTime.parse(literal.value)
    when "http://www.w3.org/2001/XMLSchema#date"
      Date.parse(literal.value)
    when "http://www.w3.org/2001/XMLSchema#boolean"
      literal.value == "true"
    when "http://www.w3.org/2001/XMLSchema#integer", "http://www.w3.org/2001/XMLSchema#int"
      literal.value.to_i
    when "http://www.w3.org/2001/XMLSchema#float", "http://www.w3.org/2001/XMLSchema#double", "http://www.w3.org/2001/XMLSchema#decimal"
      literal.value.to_f
    when "http://www.w3.org/2006/time#DateTimeInterval"
      ISO8601::TimeInterval.parse(literal.value).to_s
    when "http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON"
      JSON.parse(literal.value) rescue literal.value
    when /datatypes\/edtf/, /edtf$/i
      # Return EDTF string representation
      literal.value.to_s
    else
      # Handle language-tagged strings
      if literal.respond_to?(:language) && literal.language
        { '@value' => literal.value, '@language' => literal.language.to_s }
      else
        literal.value
      end
    end
  rescue StandardError => e
    Solis::LOGGER.warn("Error extracting value: #{e.message}")
    literal.to_s
  end

  def self.graph_name
    Solis::Options.instance.get.key?(:graphs) ? Solis::Options.instance.get[:graphs].select { |s| s['type'].eql?(:main) }&.first['name'] : ''
  end

  # Keep original methods for backward compatibility
  def self.sanitize_result(framed)
    data = framed&.key?('@graph') ? framed['@graph'] : [framed]
    sanitatize_data_in_result(data)
  end

  def self.sanitatize_data_in_result(data)
    data.map do |d|
      d.delete_if { |e| e =~ /^@/ }
      if d.is_a?(Hash)
        new_d = {}
        d.each do |k, v|
          if v.is_a?(Hash)
            if v.key?('@type')
              type = v['@type']
              if v.key?('@value')
                value = v['@value']
                case type
                when "http://www.w3.org/2001/XMLSchema#dateTime"
                  value = DateTime.parse(value)
                when "http://www.w3.org/2001/XMLSchema#date"
                  value = Date.parse(value)
                when "http://www.w3.org/2006/time#DateTimeInterval"
                  value = ISO8601::TimeInterval.parse(value)
                when "http://www.w3.org/2001/XMLSchema#boolean"
                  value = value == "true"
                end
                v = value
              end
              v = sanitize_result(v) if v.is_a?(Hash)
            end
            if v.is_a?(Hash)
              new_d[k] = v.class.method_defined?(:value) ? v.value : sanitize_result(v)
            else
              new_d[k] = v.class.method_defined?(:value) ? v.value : v
            end
          elsif v.is_a?(Array)
            new_d[k] = []
            v.each do |vt|
              if vt.is_a?(Hash)
                if vt.key?('@value')
                  new_d[k] << vt['@value']
                else
                  new_d[k] << (vt.is_a?(String) ? vt : sanitize_result(vt))
                end
              else
                new_d[k] << (vt.is_a?(String) ? vt : sanitize_result(vt))
              end
            end
            new_d[k].flatten!
          else
            new_d[k] = v.class.method_defined?(:value) ? v.value : v
          end
        end
        d = new_d
      end
      d
    end
  rescue StandardError => e
    Solis::LOGGER.error(e.message)
    data
  end
end