require 'securerandom'
require 'iso8601'
require 'hashdiff'
require 'set'
require_relative 'query'

module Solis
  class Model

    class_attribute :before_read_proc, :after_read_proc, :before_create_proc, :after_create_proc, :before_update_proc, :after_update_proc, :before_delete_proc, :after_delete_proc

    def initialize(attributes = {})
      @model_name = self.class.name
      @model_plural_name = @model_name.pluralize
      @language = Graphiti.context[:object]&.language || Solis::Options.instance.get[:language] || 'en'

      raise "Please look at /#{@model_name.tableize}/model for structure to supply" if attributes.nil?

      attributes.each do |attribute, value|
        if self.class.metadata[:attributes].keys.include?(attribute.to_s)
          if !self.class.metadata[:attributes][attribute.to_s][:node_kind].nil? && !(value.is_a?(Hash) || value.is_a?(Array) || value.class.ancestors.include?(Solis::Model))
            raise Solis::Error::InvalidAttributeError, "'#{@model_name}.#{attribute}' must be an object"
          end

          if self.class.metadata[:attributes][attribute.to_s][:node_kind].is_a?(RDF::URI) && value.is_a?(Hash)
            inner_class = self.class.metadata[:attributes][attribute.to_s][:datatype].to_s
            inner_model = self.class.graph.shape_as_model(inner_class)

            # Resolve a polymorphic reference to its concrete subclass, preferring an
            # explicit `type` key, then a full URI whose path segment names the class.
            # Keys may be strings (JSON) or symbols (internal callers).
            explicit_type = (value['type'] || value[:type] || value['@type'] || value[:'@type']).to_s
            value = value.reject { |k, _| %w[type @type].include?(k.to_s) }
            id_value = (value['id'] || value[:id]).to_s
            if !explicit_type.empty? && descendant_shape_names(inner_model.name).include?(explicit_type)
              inner_model = self.class.graph.shape_as_model(explicit_type)
            elsif !id_value.empty? && id_value.match?(self.class.graph_name)
              concrete = id_value.gsub(self.class.graph_name, '').split('/').first.classify.to_s
              if descendant_shape_names(inner_model.name).include?(concrete)
                inner_model = self.class.graph.shape_as_model(concrete)
              end
            end

            value = inner_model.new(value)
          elsif self.class.metadata[:attributes][attribute.to_s][:node_kind].is_a?(RDF::URI) && value.is_a?(Array)
            new_value = []
            value.each do |v|
              if v.is_a?(Hash)
                inner_model = self.class.graph.shape_as_model(self.class.metadata[:attributes][attribute.to_s][:datatype].to_s)
                new_value << inner_model.new(v)
              else
                new_value << v
              end
            end
            value = new_value
          end

          # switched off. currently language query parameters returns the value
          # value = {
          #   "@language" => @language,
          #   "@value" => value
          # } if self.class.metadata[:attributes][attribute.to_s][:datatype_rdf].eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#langString')

          value = value.first if value.is_a?(Array) && (attribute.eql?('id') || attribute.eql?(:id))

          instance_variable_set("@#{attribute}", value)
        else
          raise Solis::Error::InvalidAttributeError, "'#{attribute}' is not part of the definition of #{@model_name}"
        end
      end

      self.class.make_id_for(self)
    rescue StandardError => e
      Solis::LOGGER.error(e.message)
      raise Solis::Error::GeneralError, "Unable to create entity #{@model_name}"
    end

    # Removed the 'name' instance method to avoid conflicts with 'name' attributes
    # Use model_class_name instead, or access @model_name directly
    def model_class_name(plural = false)
      if plural
        @model_plural_name
      else
        @model_name
      end
    end

    def query
      raise "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?

      # before_read_proc&.call(self)
      result = Solis::Query.new(self)
      # after_read_proc&.call(result)
      result
    end

    def to_ttl(resolve_all = true)
      graph = as_graph(self, deep: resolve_all)
      graph.dump(:ttl)
    end

    def dump(format = :ttl, resolve_all = true)
      graph = as_graph(self, deep: resolve_all)
      graph.dump(format)
    end

    def to_graph(resolve_all = true)
      as_graph(self, deep: resolve_all)
    end

    def valid?
      begin
        graph = as_graph(self)
      rescue Solis::Error::InvalidAttributeError => e
        Solis::LOGGER.error(e.message)
      end

      shacl = SHACL.get_shapes(self.class.graph.instance_variable_get(:"@graph"))
      report = shacl.execute(graph)

      report.conform?
    rescue StandardError => e
      false
    end

    def destroy
      raise "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?
      sparql = Solis::Store::Sparql::Client.new(self.class.sparql_endpoint)

      raise Solis::Error::QueryError, "#{self.id} is still referenced, refusing to delete" if is_referenced?(sparql)

      before_delete_proc&.call(self)

      query = %(
with <#{self.class.graph_name}>
delete {?s ?p ?o}
where {
values ?s {<#{self.graph_id}>}
?s ?p ?o }
      )
      result = sparql.query(query)

      if result.count > 0
        if result.first.bound?(result.variable_names.first) && result.first[result.variable_names.first].value =~ /done$/
          after_delete_proc&.call(self)
        else
          after_delete_proc&.call(result)
        end
      end

      # Invalidate cached queries for this entity type
      Solis::Query.invalidate_cache_for(self.class.name)

      result
    end

    def save(validate_dependencies = true, top_level = true)
      raise "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?
      sparql = SPARQL::Client.new(self.class.sparql_endpoint)

      before_create_proc&.call(self)

      if self.exists?(sparql)
        data = properties_to_hash(self)
        result = update(data, validate_dependencies, top_level, sparql)
      else
        readonly_list = (Solis::Options.instance.get[:embedded_readonly] || []).map(&:to_s)

        # Re-type polymorphic base-class id-only references (e.g. an `agent` stub
        # that is really an `Organisatie`) to their concrete subclass, so URIs and
        # existence checks target the subclass's storage path.
        resolve_polymorphic_references!(self, sparql)

        # Enumerate the whole in-memory tree: self plus every embedded descendant.
        all_entities = collect_known_entities(self).values
        existing_ids = self.class.batch_exists?(sparql, all_entities)

        # Classify each entity: new (insert), existing embedded (update), readonly,
        # or a pure reference. readonly only protects EMBEDDED entities; the entity
        # being saved (self) is always created even when its class is a code table.
        new_entities = []
        existing_embedded = []
        all_entities.each do |entity|
          entity_exists = existing_ids.include?(entity.graph_id)
          if !entity.equal?(self) && readonly_entity?(entity, readonly_list)
            Solis::LOGGER.warn("#{entity.class.name} (id: #{entity.id}) is readonly but does not exist in database. Skipping.") unless entity_exists
          elsif !entity.equal?(self) && shallow_stub?(entity) && top_level_entity?(entity)
            # An id-only reference to an independently-addressable entity: link only.
            # It is emitted as a URI by serialize_entity; never create or rewrite it.
            raise Solis::Error::NotFoundError, "#{entity.class.name} (id: #{entity.id}) is referenced but does not exist" unless entity_exists
          elsif entity_exists
            existing_embedded << entity
          else
            new_entities << entity
          end
        end

        # Existing embedded entities are updated individually (each needs DELETE/INSERT).
        unless existing_embedded.empty?
          embedded_originals = batch_load_originals(existing_embedded)
          existing_embedded.each do |embedded|
            embedded.update(properties_to_hash(embedded), validate_dependencies, false, nil,
                            prefetched_original: embedded_originals[embedded.id])
          end
        end

        # Serialize self and every new embedded entity into one INSERT DATA operation.
        graph = RDF::Graph.new
        graph.name = RDF::URI(self.class.graph_name)
        visited = Set.new
        new_entities.each { |entity| serialize_entity(graph, entity, false, visited, []) }

        validate_graph(graph) if validate_dependencies

        Solis::LOGGER.info SPARQL::Client::Update::InsertData.new(graph, graph: graph.name).to_s if ConfigFile[:debug]

        result = sparql.insert_data(graph, graph: graph.name)
      end

      # Invalidate cached queries for this entity type
      Solis::Query.invalidate_cache_for(self.class.name)

      after_create_proc&.call(self)
      self
    rescue StandardError => e
      Solis::LOGGER.error e.message
      raise e
    end

    # Update an entity.
    #
    # @param data [Hash] the attributes to update. Must include 'id'.
    # @param validate_dependencies [Boolean] whether to validate dependencies (default: true)
    # @param top_level [Boolean] whether this is a top-level call (default: true)
    # @param sparql_client [SPARQL::Client, nil] optional reusable SPARQL client
    # @param patch [Boolean] when true, uses PATCH semantics:
    #   - Only provided attributes are changed; omitted attributes are untouched
    #   - Embedded entity arrays are merged (new IDs added, existing IDs updated,
    #     missing IDs are kept as-is — not orphaned)
    #   - No orphan detection or deletion
    #   When false (default), uses PUT semantics:
    #   - Embedded entity arrays are fully replaced
    #   - Entities removed from the array are orphaned and deleted if unreferenced
    # @param prefetched_original [Solis::Model, nil] optional pre-fetched original entity to avoid re-querying
    def update(data, validate_dependencies = true, top_level = true, sparql_client = nil, patch: false, prefetched_original: nil)
      raise Solis::Error::GeneralError, "I need a SPARQL endpoint" if self.class.sparql_endpoint.nil?

      attributes = data.include?('attributes') ? data['attributes'] : data
      raise "id is mandatory when updating" unless attributes.keys.include?('id')

      id = attributes.delete('id')
      sparql = sparql_client || SPARQL::Client.new(self.class.sparql_endpoint)

      # prefetched_original is used only when it is a complete entity; an id-only stub
      # cannot seed updated_klass (omitted mandatory attributes would be lost).
      original_klass = prefetched_original unless prefetched_original && shallow_stub?(prefetched_original)
      original_klass ||= load_original(id)
      raise Solis::Error::NotFoundError if original_klass.nil?
      updated_klass = original_klass.deep_dup

      # Cache readonly entities list once
      readonly_list = (Solis::Options.instance.get[:embedded_readonly] || []).map(&:to_s)

      # Track entities to potentially delete (only used in PUT mode)
      entities_to_check_for_deletion = {}

      # First pass: collect all embedded entities for batched existence check
      embedded_by_key = {}
      poly_cache = {}
      attributes.each_pair do |key, value|
        unless original_klass.class.metadata[:attributes][key][:node].nil?
          value = [value] unless value.is_a?(Array)
          embedded_by_key[key] = value.map do |sub_value|
            model = self.class.graph.shape_as_model(original_klass.class.metadata[:attributes][key][:datatype].to_s).new(sub_value)
            # Re-type a polymorphic base-class id-only reference to its concrete
            # subclass so existence checks and emitted URIs target the right path.
            concrete = resolve_polymorphic_class(model, sparql, poly_cache)
            model = concrete.new({ id: model.id }) if concrete && concrete != model.class
            model
          end
        end
      end

      all_embedded = embedded_by_key.values.flatten
      existing_ids = self.class.batch_exists?(sparql, all_embedded)

      # Batch-load full stored originals for embedded entities that already exist, so
      # each recursive embedded update receives a complete original (one query per class).
      existing_embedded = all_embedded.select do |e|
        existing_ids.include?(e.graph_id) && !readonly_entity?(e, readonly_list)
      end
      embedded_originals = batch_load_originals(existing_embedded)

      # Second pass: process embedded entities using batched results
      embedded_by_key.each do |key, embedded_list|
        value = attributes[key]
        value = [value] unless value.is_a?(Array)

        # Get original embedded entities for this attribute
        original_embedded = original_klass.instance_variable_get("@#{key}")
        original_embedded = [original_embedded] unless original_embedded.nil? || original_embedded.is_a?(Array)
        original_embedded ||= []

        # Track original IDs
        original_ids = original_embedded.map { |e| solis_model?(e) ? e.id : nil }.compact

        # Build new array of embedded entities
        new_embedded_values = []
        new_ids = []

        embedded_list.each do |embedded|
          new_ids << embedded.id if embedded.id
          entity_exists = existing_ids.include?(embedded.graph_id)

          if readonly_entity?(embedded, readonly_list)
            if entity_exists
              new_embedded_values << embedded
            else
              Solis::LOGGER.warn("#{embedded.class.name} (id: #{embedded.id}) is readonly but does not exist in database. Skipping.")
            end
          else
            if entity_exists
              embedded_data = properties_to_hash(embedded)
              embedded.update(embedded_data, validate_dependencies, false, nil, prefetched_original: embedded_originals[embedded.id])
              new_embedded_values << embedded
            else
              embedded_value = embedded.save(validate_dependencies, false)
              new_embedded_values << embedded_value
            end
          end
        end

        if patch
          # PATCH mode: merge new embedded entities into the original array.
          # Keep original entities that were not mentioned in the update data.
          unmentioned = original_embedded.select do |e|
            solis_model?(e) && !new_ids.include?(e.id)
          end
          merged_values = unmentioned + new_embedded_values
        else
          # PUT mode: replace the entire array; detect orphans for deletion
          merged_values = new_embedded_values

          orphaned_ids = original_ids - new_ids
          unless orphaned_ids.empty?
            orphaned_entities = original_embedded.select { |e| solis_model?(e) && orphaned_ids.include?(e.id) }
            entities_to_check_for_deletion[key] = orphaned_entities
          end
        end

        maxcount = original_klass.class.metadata[:attributes][key][:maxcount]
        embedded_value = maxcount && maxcount == 1 ? merged_values.first : merged_values
        updated_klass.instance_variable_set("@#{key}", embedded_value)
      end

      # Process non-embedded attributes
      attributes.each_pair do |key, value|
        next unless original_klass.class.metadata[:attributes][key][:node].nil?

        updated_klass.instance_variable_set("@#{key}", value)
      end

      before_update_proc&.call(original_klass, updated_klass)

      properties_original_klass = properties_to_hash(original_klass)
      properties_updated_klass = properties_to_hash(updated_klass)

      if Hashdiff.best_diff(properties_original_klass, properties_updated_klass).empty?
        Solis::LOGGER.info("#{original_klass.class.name} unchanged, skipping")
        data = original_klass
      else
        # The delete graph carries the stored original's triples; the insert graph the
        # updated entity's. Embedded children are emitted as URI references in both —
        # they are persisted by their own recursive update/save above.
        delete_graph = as_graph(original_klass, deep: false)
        insert_graph = as_graph(updated_klass, deep: false)
        where_graph = RDF::Graph.new(graph_name: RDF::URI("#{self.class.graph_name}#{tableized_class_name(self)}/#{id}"), data: RDF::Repository.new)

        if id.is_a?(Array)
          id.each do |i|
            where_graph << [RDF::URI("#{self.class.graph_name}#{tableized_class_name(self)}/#{i}"), :p, :o]
          end
        else
          where_graph << [RDF::URI("#{self.class.graph_name}#{tableized_class_name(self)}/#{id}"), :p, :o]
        end

        validate_graph(insert_graph) if validate_dependencies

        delete_insert_query = SPARQL::Client::Update::DeleteInsert.new(delete_graph, insert_graph, where_graph, graph: insert_graph.name).to_s
        delete_insert_query.gsub!('_:p', '?p')

        sparql.query(delete_insert_query)

        # Invalidate cache before verification to avoid stale reads
        Solis::Query.invalidate_cache_for(self.class.name)

        # Verify the update succeeded by re-fetching; fallback to insert if needed
        data = self.query.filter({ filters: { id: [id] } }).find_all.map { |m| m }&.first
        if data.nil?
          sparql.insert_data(insert_graph, graph: insert_graph.name)
          data = updated_klass
        end

        # Delete orphaned entities after successful update (PUT mode only)
        delete_orphaned_entities(entities_to_check_for_deletion, sparql) unless patch
      end

      # Invalidate cached queries for this entity type
      Solis::Query.invalidate_cache_for(self.class.name)

      after_update_proc&.call(updated_klass, data)

      data
    rescue StandardError => e
      original_graph = as_graph(original_klass, deep: false) if defined?(original_klass) && original_klass
      Solis::LOGGER.error(e.message)
      Solis::LOGGER.error original_graph.dump(:ttl) if defined?(original_graph) && original_graph
      Solis::LOGGER.error delete_insert_query if defined?(delete_insert_query)
      sparql.insert_data(original_graph, graph: original_graph.name) if defined?(original_graph) && original_graph && defined?(sparql) && sparql

      raise e
    end

    def graph_id
      "#{self.class.graph_name}#{tableized_class_name(self)}/#{self.id}"
    end

    def is_referenced?(sparql)
      sparql.query("ASK WHERE { ?s ?p <#{self.graph_id}>. filter (!contains(str(?s), 'audit') && !contains(str(?p), 'audit'))}")
    end

    def exists?(sparql)
      sparql.query("ASK WHERE { <#{self.graph_id}> ?p ?o }")
    end

    # Save multiple entities in a single SPARQL INSERT operation.
    # Entities that already exist are updated individually.
    # @param entities [Array<Solis::Model>] entities to save
    # @param validate_dependencies [Boolean] whether to validate dependencies
    # @param batch_size [Integer] max entities per INSERT (default 100)
    # @return [Array<Solis::Model>] the saved entities
    def self.batch_save(entities, validate_dependencies: true, batch_size: 100)
      raise "I need a SPARQL endpoint" if sparql_endpoint.nil?
      return [] if entities.empty?

      sparql = SPARQL::Client.new(sparql_endpoint)

      # Batch check existence of all entities
      existing_ids = batch_exists?(sparql, entities)

      to_create = []
      to_update = []

      entities.each do |entity|
        if existing_ids.include?(entity.graph_id)
          to_update << entity
        else
          to_create << entity
        end
      end

      # Batch insert: combine new entity graphs into single INSERT DATA operations
      unless to_create.empty?
        to_create.each_slice(batch_size) do |batch|
          combined_graph = RDF::Graph.new
          combined_graph.name = RDF::URI(graph_name)
          visited = Set.new

          batch.each do |entity|
            entity.before_create_proc&.call(entity)
            entity.send(:serialize_entity, combined_graph, entity, true, visited, [])
          end

          sparql.insert_data(combined_graph, graph: combined_graph.name)

          batch.each { |entity| entity.after_create_proc&.call(entity) }
        end

        # Invalidate cache once for the entity type
        Solis::Query.invalidate_cache_for(name)
      end

      # Updates still processed individually (DELETE/INSERT requires per-entity WHERE)
      to_update.each do |entity|
        data = entity.send(:properties_to_hash, entity)
        entity.update(data, validate_dependencies, true, sparql)
      end

      entities
    end

    # Check existence of multiple entities in a single SPARQL query
    # Returns a Set of graph_ids that exist
    def self.batch_exists?(sparql, entities)
      return Set.new if entities.empty?
      return Set.new([entities.first.graph_id]) if entities.size == 1 && entities.first.exists?(sparql)
      return Set.new if entities.size == 1

      values = entities.map { |e| "<#{e.graph_id}>" }.join(' ')
      query = "SELECT DISTINCT ?s WHERE { VALUES ?s { #{values} } . ?s ?p ?o }"
      results = sparql.query(query)
      Set.new(results.map { |r| r[:s].to_s })
    end

    def self.make_id_for(model)
      id = model.instance_variable_get("@id")
      if id.nil? || (id.is_a?(String) && id&.empty?)
        id = SecureRandom.uuid
        LOGGER.info("ID(#{id}) generated for #{self.name}") if ConfigFile[:debug]
        model.instance_variable_set("@id", id)
      elsif id.to_s =~ /^https?:\/\//
        id = id.to_s.split('/').last
        LOGGER.info("ID(#{id}) normalised for #{self.name}") if ConfigFile[:debug]
        model.instance_variable_set("@id", id)
      end
      model
    rescue StandardError => e
      Solis::LOGGER.error(e.message)
      raise Solis::Error::GeneralError, "Error generating id for #{self.name}"
    end

    def self.metadata
      @metadata
    end

    def self.metadata=(m)
      @metadata = m
    end

    def self.shapes=(s)
      @shapes = s
    end

    def self.shapes
      @shapes
    end

    def self.graph_name
      @graph_name
    end

    def self.graph_name=(graph_name)
      @graph_name = graph_name
    end

    def self.graph_prefix=(graph_prefix)
      @graph_prefix = graph_prefix
    end

    def self.graph_prefix
      @graph_prefix
    end

    def self.sparql_endpoint
      @sparql_endpoint
    end

    def self.sparql_endpoint=(sparql_endpoint)
      @sparql_endpoint = sparql_endpoint
    end

    def self.graph
      @graph
    end

    def self.graph=(graph)
      @graph = graph
    end

    def self.language
      Graphiti.context[:object]&.language || Solis::Options.instance.get[:language] || @language || 'en'
    end

    def self.language=(language)
      @language = language
    end

    def self.model(level = 0)
      m = { type: self.name.tableize, attributes: [] }
      self.metadata[:attributes].each do |attribute, attribute_metadata|
        if attribute_metadata.key?(:class) && !attribute_metadata[:class].nil? && attribute_metadata[:class].value =~ /#{self.graph_name}/ && level == 0
          cm = self.graph.shape_as_model(self.metadata[:attributes][attribute][:datatype].to_s).model(level + 1)
        end

        attribute_data = { name: attribute,
                           label: attribute_metadata[:label] || {},
                           data_type: attribute_metadata[:datatype],
                           mandatory: (attribute_metadata[:mincount].to_i > 0),
                           repeatable: (attribute_metadata[:maxcount].to_i > 1 || attribute_metadata[:maxcount].nil?),
                           description: attribute_metadata[:comment]&.value
        }
        attribute_data[:order] = attribute_metadata[:order]&.value.to_i if attribute_metadata.key?(:order) && !attribute_metadata[:order].nil?
        attribute_data[:group] = attribute_metadata[:group]&.value.gsub(graph_name,'').gsub(/Group$/,'') if attribute_metadata.key?(:group) && !attribute_metadata[:group].nil?
        attribute_data[:attributes] = cm[:attributes] if cm && cm[:attributes]

        m[:attributes] << attribute_data
      end

      m
    end

    def self.model_template(level = 0)
      m = { type: self.name.tableize, attributes: {} }
      self.metadata[:attributes].each do |attribute, attribute_metadata|

        if attribute_metadata.key?(:class) && !attribute_metadata[:class].nil? && attribute_metadata[:class].value =~ /#{self.graph_name}/ && level == 0
          cm = self.graph.shape_as_model(self.metadata[:attributes][attribute][:datatype].to_s).model_template(level + 1)
          m[:attributes][attribute.to_sym] = cm[:attributes]
        else
          m[:attributes][attribute.to_sym] = ''
        end
      end

      m
    end

    def self.construct(level = 0)
      raise 'to be implemented'
    end

    def self.model_before_read(&blk)
      self.before_read_proc = blk
    end

    def self.model_after_read(&blk)
      self.after_read_proc = blk
    end

    def self.model_before_create(&blk)
      self.before_create_proc = blk
    end

    def self.model_after_create(&blk)
      self.after_create_proc = blk
    end

    def self.model_before_update(&blk)
      self.before_update_proc = blk
    end

    def self.model_after_update(&blk)
      self.after_update_proc = blk
    end

    def self.model_before_delete(&blk)
      self.before_delete_proc = blk
    end

    def self.model_after_delete(&blk)
      self.after_delete_proc = blk
    end

    private

    # Walk the in-memory entity tree and collect every entity by UUID
    # ({ uuid => entity }), following embedded (node_kind) attributes.
    def collect_known_entities(entity, collected = {})
      uuid = entity.instance_variable_get("@id")
      return collected if uuid.nil? || collected.key?(uuid)
      collected[uuid] = entity
      entity.class.metadata[:attributes].each do |attr, meta|
        next if meta[:node_kind].nil?
        val = entity.instance_variable_get("@#{attr}")
        next if val.nil?
        Array(val).each { |v| collect_known_entities(v, collected) if solis_model?(v) }
      end
      collected
    end

    # Helper method to check if an object is a Solis model
    def solis_model?(obj)
      obj.class.ancestors.include?(Solis::Model)
    end

    # True when only the entity's id is populated — an id-only stub, e.g. an embedded
    # relation materialised by Query#graph_to_object as Model.new(id:).
    def shallow_stub?(entity)
      return false unless solis_model?(entity)
      entity.class.metadata[:attributes].each_key.none? do |attr|
        attr.to_s != 'id' && !entity.instance_variable_get("@#{attr}").nil?
      end
    end

    # Map of shape_name => parent_shape_name, derived from each shape's sh:node
    # (target_node) pointing at "<graph_name><Parent>Shape". Pure metadata.
    def polymorphic_parent_map
      graph_name = self.class.graph_name
      map = {}
      self.class.shapes.each do |name, meta|
        tn = meta[:target_node]
        next if tn.nil?
        if tn.to_s =~ /^#{Regexp.escape(graph_name)}(.+)Shape$/
          parent = $1
          map[name] = parent unless parent == name
        end
      end
      map
    end

    # Names of shapes that inherit (directly or transitively, via sh:node) from
    # base_shape_name — i.e. the concrete subclasses of a polymorphic base.
    def descendant_shape_names(base_shape_name)
      parent_of = polymorphic_parent_map
      parent_of.keys.select do |name|
        ancestor = parent_of[name]
        found = false
        while ancestor
          if ancestor == base_shape_name
            found = true
            break
          end
          ancestor = parent_of[ancestor]
        end
        found
      end
    end

    # For a polymorphic id-only stub declared as a base class, ask the store which
    # concrete subclass URI actually holds this id, and return that concrete model
    # class. Returns nil when the declared class has no subclasses (not polymorphic)
    # or no matching subject exists. Write-path only — issues a SPARQL query.
    def resolve_polymorphic_class(stub, sparql, cache = {})
      return nil unless solis_model?(stub) && shallow_stub?(stub) && stub.id

      base_name = stub.class.name
      # Key by declared class + id: the same id may be referenced through different
      # declared relation types, so a nil for one base must not shadow another.
      cache_key = "#{base_name}|#{stub.id}"
      return cache[cache_key] if cache.key?(cache_key)

      subclass_names = descendant_shape_names(base_name)
      return cache[cache_key] = nil if subclass_names.empty?

      graph_name = stub.class.graph_name
      candidates = ([base_name] + subclass_names).uniq.map { |name| "#{graph_name}#{name.tableize}/#{stub.id}" }
      values = candidates.map { |u| "<#{u}>" }.join(' ')
      result = sparql.query("SELECT ?s WHERE { VALUES ?s { #{values} } . ?s ?p ?o } LIMIT 1")
      uri = result.first && result.first[:s] && result.first[:s].to_s

      klass = nil
      unless uri.nil?
        concrete_name = uri.sub(graph_name, '').split('/').first.classify
        klass = self.class.graph.shape_as_model(concrete_name) if self.class.graph.shape?(concrete_name)
      end
      cache[cache_key] = klass
    end

    # Walk the relation tree and re-type every polymorphic base-class id-only stub
    # to its concrete subclass (resolved from the store), so existence checks and
    # emitted reference URIs use the subclass's storage path. Write-path only.
    def resolve_polymorphic_references!(entity, sparql, cache = {}, visited = Set.new)
      return entity if visited.include?(entity.object_id)
      visited << entity.object_id
      entity.class.metadata[:attributes].each do |attr, meta|
        next if meta[:node_kind].nil?
        val = entity.instance_variable_get("@#{attr}")
        next if val.nil?
        if val.is_a?(Array)
          entity.instance_variable_set("@#{attr}", val.map { |v| retype_polymorphic_stub(v, sparql, cache, visited) })
        else
          entity.instance_variable_set("@#{attr}", retype_polymorphic_stub(val, sparql, cache, visited))
        end
      end
      entity
    end

    # Resolve a single relation value: re-type a polymorphic base stub to its
    # concrete subclass, then recurse. Non-model values pass through unchanged.
    def retype_polymorphic_stub(v, sparql, cache, visited)
      return v unless solis_model?(v)
      concrete = resolve_polymorphic_class(v, sparql, cache)
      v = concrete.new({ id: v.id }) if concrete && concrete != v.class
      resolve_polymorphic_references!(v, sparql, cache, visited)
      v
    end

    # Load the full stored entity for this model's class by id. Returns nil when absent.
    def load_original(id)
      self.query.filter({ language: self.class.language, filters: { id: [id] } })
          .find_all.map { |m| m }&.first
    end

    # Load full stored originals for the given embedded models, one query per class.
    # Returns { id => full_entity }.
    def batch_load_originals(models)
      originals = {}
      models.select { |m| solis_model?(m) && m.id }.group_by(&:class).each do |_klass, group|
        ids = group.map(&:id).uniq
        group.first.query
             .filter({ language: group.first.class.language, filters: { id: ids } })
             .find_all.each { |entity| originals[entity.id] = entity }
      end
      originals
    end

    # Helper method to check if an entity is readonly (code table)
    def readonly_entity?(entity, readonly_list = nil)
      readonly_list ||= (Solis::Options.instance.get[:embedded_readonly] || []).map(&:to_s)
      (entity.class.ancestors.map(&:to_s) & readonly_list).any?
    end

    # Helper method to check if an entity is a top-level entity (has its own shape definition).
    # Top-level entities are independently addressable and should not be cascade-deleted
    # when unlinked from a parent, unless explicitly opted in via embedded_delete config.
    def top_level_entity?(entity)
      self.class.graph.shape?(entity.class.name)
    end

    # Helper method to get tableized class name
    def tableized_class_name(obj)
      obj.class.name.tableize
    end

    # Helper method to build entity URI
    def build_entity_uri(entity_or_class, entity_id = nil)
      if entity_or_class.is_a?(Class)
        class_name = entity_or_class.name
        id = entity_id
      else
        class_name = entity_or_class.class.name
        id = entity_id || entity_or_class.id
      end
      RDF::URI("#{self.class.graph_name}#{class_name.tableize}/#{id}")
    end

    # Delete orphaned entities that are no longer referenced.
    #
    # Decision logic (in order of precedence):
    # 1. embedded_readonly → never delete (code tables)
    # 2. Top-level entity (has own shape) + NOT in embedded_delete → unlink only, don't delete
    # 3. Top-level entity + listed in embedded_delete → delete (opt-in override)
    # 4. Still referenced by other entities (batch_referenced?) → never delete (safety net)
    def delete_orphaned_entities(entities_to_check, sparql)
      return if entities_to_check.nil? || entities_to_check.empty?

      readonly_list = (Solis::Options.instance.get[:embedded_readonly] || []).map(&:to_s)
      delete_list = (Solis::Options.instance.get[:embedded_delete] || []).map(&:to_s)

      # Collect all deletable orphans
      deletable_orphans = []
      entities_to_check.each do |_key, orphaned_entities|
        next if orphaned_entities.nil?
        orphaned_entities.each do |orphaned_entity|
          next unless solis_model?(orphaned_entity)

          # 1. Never delete readonly entities (code tables)
          if readonly_entity?(orphaned_entity, readonly_list)
            Solis::LOGGER.info("#{orphaned_entity.class.name} (id: #{orphaned_entity.id}) is in embedded_readonly list. Skipping deletion.")
            next
          end

          # 2. Top-level entities are never auto-deleted unless opted in via embedded_delete
          if top_level_entity?(orphaned_entity)
            explicitly_deletable = (orphaned_entity.class.ancestors.map(&:to_s) & delete_list).any?
            unless explicitly_deletable
              Solis::LOGGER.info("#{orphaned_entity.class.name} (id: #{orphaned_entity.id}) is a top-level entity. Skipping deletion (unlink only).")
              next
            end
          end

          deletable_orphans << orphaned_entity
        end
      end

      return if deletable_orphans.empty?

      # 4. Safety net: batch check which orphans are still referenced elsewhere
      referenced_ids = batch_referenced?(sparql, deletable_orphans)

      deletable_orphans.each do |orphaned_entity|
        if referenced_ids.include?(orphaned_entity.graph_id)
          Solis::LOGGER.info("#{orphaned_entity.class.name} (id: #{orphaned_entity.id}) is still referenced elsewhere. Skipping deletion.")
          next
        end

        begin
          Solis::LOGGER.info("Deleting orphaned entity: #{orphaned_entity.class.name} (id: #{orphaned_entity.id})")
          orphaned_entity.destroy
        rescue StandardError => e
          Solis::LOGGER.error("Failed to delete orphaned entity #{orphaned_entity.class.name} (id: #{orphaned_entity.id}): #{e.message}")
        end
      end
    end

    # Batch check which entities are still referenced by other entities
    # Returns a Set of graph_ids that are referenced
    def batch_referenced?(sparql, entities)
      return Set.new if entities.empty?

      values = entities.map { |e| "<#{e.graph_id}>" }.join(' ')
      query = "SELECT DISTINCT ?o WHERE { VALUES ?o { #{values} } . ?s ?p ?o . FILTER(!CONTAINS(STR(?s), 'audit') && !CONTAINS(STR(?p), 'audit')) }"
      results = sparql.query(query)
      Set.new(results.map { |r| r[:o].to_s })
    end

    # Build an RDF::Graph for `entity`. Pure: reads only the in-memory entity tree,
    # never the store, and performs no validation. Embedded children are emitted as
    # URI references; when `deep` is true, embedded children that carry their own
    # data (i.e. are not id-only references) are also serialized into the graph.
    def as_graph(entity = self, deep: false)
      graph = RDF::Graph.new
      graph.name = RDF::URI(self.class.graph_name)
      serialize_entity(graph, entity, deep, Set.new, [])
      graph
    end

    # Emit `entity`'s own triples (rdf:type + attribute statements) into `graph` and
    # return the entity URI. `visited` guards against emitting the same entity twice;
    # `hierarchy` guards against same-class recursion cycles.
    def serialize_entity(graph, entity, deep, visited, hierarchy)
      uuid = entity.id
      id = build_entity_uri(entity)
      return id if uuid && visited.include?(uuid)
      visited << uuid

      metadata = entity.class.metadata
      hierarchy.push("#{entity.class.name}(#{uuid})")
      graph << [id, RDF::RDFV.type, metadata[:target_class]]

      metadata[:attributes].each do |attribute, attr_metadata|
        serialize_attribute(graph, id, entity, attribute, attr_metadata, deep, visited, hierarchy)
      end

      hierarchy.pop
      id
    rescue StandardError => e
      Solis::LOGGER.error(e.message)
      raise e
    end

    # Emit the statements for a single attribute of `entity` into `graph`.
    # For embedded attributes the child is emitted as a URI reference; when `deep`
    # is true a child carrying its own data is also serialized into `graph`.
    def serialize_attribute(graph, id, entity, attribute, metadata, deep, visited, hierarchy)
      data = entity.instance_variable_get("@#{attribute}")

      # cardinality (min) check — mandatory attribute must be present
      if data.nil? && metadata.key?(:mincount) && (metadata[:mincount].nil? || metadata[:mincount] > 0) &&
         graph.query(RDF::Query.new({ attribute.to_sym => { RDF.type => metadata[:node] } })).size == 0
        raise Solis::Error::InvalidAttributeError,
              "#{hierarchy.join('.')}~#{entity.class.name}.#{attribute} min=#{metadata[:mincount]} and max=#{metadata[:maxcount]}"
      end

      # skip if nil or an empty container
      return if data.nil? || ([Hash, Array, String].include?(data.class) && data.empty?)

      case metadata[:datatype_rdf]
      when 'http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON'
        data = data.to_json
      end

      # coerce embedded hashes to model instances
      unless metadata[:node_kind].nil?
        model = self.class.graph.shape_as_model(metadata[:datatype].to_s)
        if data.is_a?(Hash)
          data = model.new(data)
        elsif data.is_a?(Array)
          data = data.map { |m| m.is_a?(Hash) ? model.new(m) : m }
        end
      end

      data = [data] unless data.is_a?(Array)

      data.each do |d|
        if solis_model?(d) && self.class.graph.shape?(d.class.name)
          if deep && !shallow_stub?(d) && hierarchy.none? { |s| s.start_with?("#{d.class.name}(") }
            d = serialize_entity(graph, d, deep, visited, hierarchy)
          else
            d = "#{self.class.graph_name}#{d.class.name.tableize}/#{d.id}"
          end
        end

        d = d.first if d.is_a?(Array) && d.length == 1

        d = coerce_literal(d, metadata, attribute, hierarchy)

        Array(d).each { |v| graph << [id, RDF::URI("#{metadata[:path]}"), v] }
      end
    end

    # Coerce a serialized value to its RDF term according to the attribute datatype.
    def coerce_literal(d, metadata, attribute, hierarchy)
      if metadata[:datatype_rdf].eql?('http://www.w3.org/1999/02/22-rdf-syntax-ns#langString')
        if d.is_a?(Hash) && (d.keys - ["@language", "@value"]).size == 0
          if d['@value'].is_a?(Array)
            d['@value'].map { |v| RDF::Literal.new(v, language: d['@language']) }
          else
            RDF::Literal.new(d['@value'], language: d['@language'])
          end
        else
          RDF::Literal.new(d, language: @language)
        end
      elsif metadata[:datatype_rdf].eql?('http://www.w3.org/2001/XMLSchema#anyURI')
        RDF::Literal.new(d.to_s, datatype: RDF::XSD.anyURI)
      elsif metadata[:node].is_a?(RDF::URI)
        RDF::URI(d)
      elsif metadata[:datatype_rdf] =~ /datatypes\/edtf/ || metadata[:datatype_rdf] =~ /edtf$/i
        begin
          RDF::Literal::EDTF.new(d)
        rescue StandardError => e
          raise Solis::Error::InvalidDatatypeError, "#{hierarchy.join('.')}.#{attribute}: #{e.message}"
        end
      elsif metadata[:datatype_rdf].eql?('http://www.w3.org/2006/time#DateTimeInterval')
        begin
          RDF::Literal.new(ISO8601::TimeInterval.parse(d).to_s, datatype: metadata[:datatype_rdf])
        rescue StandardError => e
          raise Solis::Error::InvalidDatatypeError, "#{hierarchy.join('.')}.#{attribute}: #{e.message}"
        end
      else
        datatype = RDF::Vocabulary.find_term(metadata[:datatype_rdf])
        datatype = metadata[:node] if datatype.nil?
        datatype = metadata[:datatype_rdf] if datatype.nil?
        RDF::Literal.new(d, datatype: datatype)
      end
    end

    # Validate a serialized insert graph according to the configured :validation mode
    # (Solis::Options key :validation):
    #   :cardinality (default) — no extra check; minCount is already enforced inline
    #                            during serialization (raises InvalidAttributeError).
    #   :warn                  — run full SHACL, log every non-conformance as a warning.
    #   :full                  — run full SHACL, raise InvalidAttributeError on any.
    def validate_graph(graph)
      mode = (Solis::Options.instance.get[:validation] || :cardinality).to_sym
      return if mode == :cardinality

      shapes = SHACL.get_shapes(self.class.graph.instance_variable_get(:@graph))
      report = shapes.execute(graph)
      return if report.conform?

      messages = Array(report.results).map do |r|
        r.respond_to?(:message) ? Array(r.message).join(', ') : r.to_s
      end

      if mode == :warn
        messages.each { |m| Solis::LOGGER.warn("SHACL: #{m}") }
      else
        raise Solis::Error::InvalidAttributeError, "SHACL validation failed: #{messages.join('; ')}"
      end
    end

    def properties_to_hash(model)
      n = {}
      model.class.metadata[:attributes].each_key do |m|
        if model.instance_variable_get("@#{m}").is_a?(Array)
          n[m] = model.instance_variable_get("@#{m}").map { |iv| iv.class.ancestors.include?(Solis::Model) ? properties_to_hash(iv) : iv }
        elsif model.instance_variable_get("@#{m}").class.ancestors.include?(Solis::Model)
          n[m] = properties_to_hash(model.instance_variable_get("@#{m}"))
        else
          n[m] = model.instance_variable_get("@#{m}")
        end
      end

      n.compact!
      n
    end
  end
end