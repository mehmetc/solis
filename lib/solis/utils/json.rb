

module Solis
  module Utils
    module JSONUtils

      def self.deep_replace_prefix_in_name_attr(obj, prefix_old, prefix_new)
        obj2 = Marshal.load(Marshal.dump(obj))
        obj.each_key do |name_attr|
          if name_attr.start_with?(prefix_old)
            name_attr_new = name_attr.sub(prefix_old, prefix_new)
            obj2.transform_keys!({name_attr => name_attr_new})
            name_attr = name_attr_new
          end
          val_attr = obj2[name_attr]
          if val_attr.is_a?(Hash)
            obj2[name_attr] = deep_replace_prefix_in_name_attr(val_attr, prefix_old, prefix_new)
          elsif val_attr.is_a?(Array)
            val_attr.each_with_index do |e, i|
              if e.is_a?(Hash)
                obj2[name_attr][i] = deep_replace_prefix_in_name_attr(e, prefix_old, prefix_new)
              end
            end
          end
        end
        obj2
      end

      def self.delete_empty_attributes!(obj)
        obj.each do |name_attr, val_attr|
          if [Array, Hash].include?(val_attr.class) && val_attr.empty?
            obj[name_attr] = '@unset'
          else
            if val_attr.is_a?(Array)
              val_attr.each do |e|
                if e.is_a?(Hash)
                  delete_empty_attributes!(e)
                end
              end
            elsif val_attr.is_a?(Hash)
              delete_empty_attributes!(val_attr)
            end
          end
        end
      end

      # very smart: https://stackoverflow.com/a/50471832
      def self.recursive_compact!(hash_or_array, exclude_types=[])
        p = proc do |*args|
          v = args.last
          v.delete_if(&p) if v.respond_to?(:delete_if)
          v.nil? || v.respond_to?(:"empty?") && v.empty? && !exclude_types.include?(v.class)
        end
        hash_or_array.delete_if(&p)
      end

    end
  end
end
