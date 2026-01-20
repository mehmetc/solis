require 'graphiti'
module Solis
  class SparqlAdaptor < Graphiti::Adapters::Abstract
    def self.sideloading_classes
      {
        has_many: HasMany,
        belongs_to: BelongsTo,
        has_one: ::Graphiti::Sideload::HasOne,
        many_to_many: ::Graphiti::Sideload::ManyToMany,
        polymorphic_belongs_to: ::Graphiti::Sideload::PolymorphicBelongsTo
      }
    end

    def base_scope(*scope)
      types = ObjectSpace.each_object(Class).select { |klass| klass < self.resource.model}.map{|m| m.name.tableize.pluralize.to_sym}
      types <<  self.resource.model.name.tableize.pluralize.to_sym if types.empty?

      { type: types, sort: {}, filters: {} }
    rescue Exception => e
      types = [self.resource.model.name.tableize.pluralize.to_sym]
      { type: types, sort: {}, filters: {} }
    end

    def paginate(scope, current, per)
      scope.merge!(current_page: current, per_page: per)
    end

    def count(scope, attr)
      count = self.resource.model.new().query.paging(scope).filter(scope).sort(scope).count
      scope[attr] = count
    end

    def order(scope, att, dir)
      scope[:sort].merge!({ att => dir })
      scope
    end

    def self.default_operators
      {
        string: [:eq, :not_eq, :contains],
        lang_string: [:eq, :not_eq, :contains],
        integer: [:eq, :not_eq, :gt, :lt],
        float: [:eq, :not_eq, :gt, :lt],
        big_decimal: [:eq, :not_eq, :gt, :lt],
        date: [:eq, :not_eq, :gt, :gte, :lt, :lte],
        boolean: [:eq, :not_eq],
        uuid: [:eq, :not_eq],
        enum: [:eq],
        datetime: [:eq, :not_eq, :gt, :lt],
        anyuri: [:eq, :not_eq],
      }
    end


    def filter(scope, attribute, value, is_not = false, operator = '=')
      scope[:filters][attribute] = {value: value, operator: operator, is_not: is_not}
      scope
    end

    alias :filter_eq :filter
    alias :filter_string_eq :filter
    alias :filter_integer_eq :filter
    alias :filter_float_eq :filter
    alias :filter_big_decimal_eq :filter
    alias :filter_date_eq :filter
    alias :filter_boolean_eq :filter
    alias :filter_uuid_eq :filter
    alias :filter_enum_eq :filter
    alias :filter_datetime_eq :filter
    alias :filter_lang_string_eq :filter
    alias :filter_anyuri_eq :filter

    def filter_not_eq(scope, attribute, value)
      filter_eq(scope, attribute, value, true, '=')
    end

    alias :filter_string_not_eq :filter_not_eq
    alias :filter_integer_not_eq :filter_not_eq
    alias :filter_float_not_eq :filter_not_eq
    alias :filter_big_decimal_not_eq :filter_not_eq
    alias :filter_date_not_eq :filter_not_eq
    alias :filter_boolean_not_eq :filter_not_eq
    alias :filter_uuid_not_eq :filter_not_eq
    alias :filter_enum_not_eq :filter_not_eq
    alias :filter_datetime_not_eq :filter_not_eq
    alias :filter_lang_string_not_eq :filter_not_eq
    alias :filter_anyuri_not_eq :filter_not_eq

    def filter_contains(scope, attribute, value)
      filter_eq(scope, attribute, value, false, '~')
    end

    alias :filter_string_contains :filter_contains
    alias :filter_lang_string_contains :filter_contains

    def filter_gt(scope, attribute, value)
      filter_eq(scope, attribute, value, false, '>')
    end

    alias :filter_string_gt :filter_gt
    alias :filter_integer_gt :filter_gt
    alias :filter_float_gt :filter_gt
    alias :filter_big_decimal_gt :filter_gt
    alias :filter_date_gt :filter_gt
    alias :filter_boolean_gt :filter_gt
    alias :filter_uuid_gt :filter_gt
    alias :filter_enum_gt :filter_gt
    alias :filter_datetime_gt :filter_gt

    def filter_not_gt(scope, attribute, value)
      filter_eq(scope, attribute, value, true, '>')
    end

    alias :filter_string_not_gt :filter_not_gt
    alias :filter_integer_not_gt :filter_not_gt
    alias :filter_float_not_gt :filter_not_gt
    alias :filter_big_decimal_not_gt :filter_not_gt
    alias :filter_date_not_gt :filter_not_gt
    alias :filter_boolean_not_gt :filter_not_gt
    alias :filter_uuid_not_gt :filter_not_gt
    alias :filter_enum_not_gt :filter_not_gt
    alias :filter_datetime_not_gt :filter_not_gt

    def filter_lt(scope, attribute, value)
      filter_eq(scope, attribute, value, false, '<')
    end

    alias :filter_string_lt :filter_lt
    alias :filter_integer_lt :filter_lt
    alias :filter_float_lt :filter_lt
    alias :filter_big_decimal_lt :filter_lt
    alias :filter_date_lt :filter_lt
    alias :filter_boolean_lt :filter_lt
    alias :filter_uuid_lt :filter_lt
    alias :filter_enum_lt :filter_lt
    alias :filter_datetime_lt :filter_lt

    def filter_not_lt(scope, attribute, value)
      filter_eq(scope, attribute, value, true, '<')
    end

    alias :filter_string_not_lt :filter_not_lt
    alias :filter_integer_not_lt :filter_not_lt
    alias :filter_float_not_lt :filter_not_lt
    alias :filter_big_decimal_not_lt :filter_not_lt
    alias :filter_date_not_lt :filter_not_lt
    alias :filter_boolean_not_lt :filter_not_lt
    alias :filter_uuid_not_lt :filter_not_lt
    alias :filter_enum_not_lt :filter_not_lt
    alias :filter_datetime_not_lt :filter_not_lt

    def filter_gte(scope, attribute, value)
      filter_eq(scope, attribute, value, false, '>=')
    end

    alias :filter_date_gte :filter_gte

    def filter_not_gte(scope, attribute, value)
      filter_eq(scope, attribute, value, true, '>=')
    end

    alias :filter_date_not_gte :filter_not_gte

    def filter_lte(scope, attribute, value)
      filter_eq(scope, attribute, value, false, '<=')
    end

    alias :filter_date_lte :filter_lte

    def filter_not_lte(scope, attribute, value)
      filter_eq(scope, attribute, value, true, '<=')
    end

    alias :filter_date_not_lte :filter_not_lte

    def transaction(*)
      yield
    end

    # def destroy(model_instance)
    #   super
    # end

    # def save(model_instance)
    #   pp model_instance
    # end
    #
    # def build(model_class)
    #   model_class.new
    # end
    #
    # def assign_attributes(model_instance, attributes)
    #   attributes.each_pair do |key, value|
    #     model_instance.send(:"#{key}=", value)
    #   end
    # end

    # def associate(parent, child, association_name, association_type)
    #   pp parent, children, association_name, association_type
    #   super
    # end
    #
    # def associate_all(parent, children, association_name, association_type)
    #   pp parent, children, association_name, association_type
    #   super
    # end
    #
    # def disassociate(parent, child, association_name, association_type)
    #   pp parent, children, association_name, association_type
    #   super
    # end

    def resolve(scope)
      self.resource.model.before_read_proc&.call(scope)
      query = self.resource.model.new().query.paging(scope).filter(scope).sort(scope)
      data = query.find_all.map { |m|
        m
      }
      self.resource.model.after_read_proc&.call(data)
      data
    end

    # def associate_all(parent, children, association_name, association_type)
    #   children.each do |c|
    #     associate(parent, c, association_name, association_type)
    #   end
    # end

    # geeft fout als associate super gebruikt wordt
    # http://127.0.0.1:9292/autocirculaties?filter%5Bgebruiker_id%5D%5Beq%5D=1221&include=uitleenformaat,wat_uitlenen
    def associate(parent, child, association_name, association_type)
      if activerecord_associate?(parent, child, association_name)
        activerecord_adapter.associate \
            parent, child, association_name, association_type
      elsif [:has_many, :many_to_many].include?(association_type)
        if parent.send(:"#{association_name}").nil?
          parent.send(:"#{association_name}=", [child])
        else
          parent_child_data = parent.send(:"#{association_name}")

          if parent_child_data.is_a?(Array)
            parent_child_data = parent_child_data.map do |m|
              m.id.eql?(child.id) ? child : m
            end
          else
            if parent_child_data.id.eql?(child.id)
              parent_child_data = [child]
            # else
            #   parent_child_data = nil
            end
          end

          parent.send(:"#{association_name}=", parent_child_data)
          #parent.send(:"#{association_name}") << child
        end
      else
        parent_child_data = parent.send(:"#{association_name}")

        if parent_child_data.is_a?(Array)
          parent_child_data = parent_child_data.map do |m|
            m.id.eql?(child.id) ? child : m
          end
        else
          if parent_child_data&.id.eql?(child.id)
            parent_child_data = [child]
          else
            parent_child_data = nil
          end
        end

        parent.send(:"#{association_name}=", parent_child_data)
      end
    end
  end

  class BelongsTo < Graphiti::Sideload::BelongsTo
    def load_params(parents, query)
      query.hash.tap do |hash|
        hash[:filter] ||= {}
        unless hash[:filter].include?(:id)
          all_ids = parents.map{|m| m.instance_variable_get("@#{query.association_name.to_s}")}.flatten.map{|m| m.instance_variable_get("@#{primary_key}")}.uniq.compact.join(',')

          hash[:filter].merge!({primary_key => all_ids})
        end
      end
    end

    private

    # relations are included here
    def children_for(parent, map)
      map.values
    end

    # def child_map(children)
    #   children.index_by(&primary_key)
    # end
    #
    # def children_for(parent, map)
    #   fk = parent.send(name).send(foreign_key) rescue nil #TODO: this is bad
    #   children = map[fk]
    #   return children if children
    #
    #   keys = map.keys
    #   if fk.is_a?(String) && keys[0].is_a?(Integer)
    #     fk = fk.to_i
    #   elsif fk.is_a?(Integer) && keys[0].is_a?(String)
    #     fk = fk.to_s
    #   end
    #   map[fk] || []
    # end
  end


  class HasMany  < Graphiti::Sideload::HasMany
    def inverse_filter
      @inverse_filter || foreign_key
    end

    def load_params(parents, query)
      query.hash.tap do |hash|
        hash[:filter] ||= {}
        unless hash[:filter].include?(:id)
          all_ids = parents.map{|m| m.instance_variable_get("@#{query.association_name.to_s}")}.flatten.map{|m| m.instance_variable_get("@#{primary_key}")}.uniq.compact.join(',')

          hash[:filter].merge!({primary_key => all_ids})
        end
      end
    end

    def children_for(parent, map)
      map.values.flatten
    end

    def link_filter(parents)
      {inverse_filter => parent_filter(parents)}
    end

    private

    def parent_filter(parents)
      ids_for_parents(parents).join(",")
    end
  end
end