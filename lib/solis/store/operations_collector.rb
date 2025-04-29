

require_relative 'common'


module Solis
  class Store

    module OperationsCollector
      # Expects:
      # - @ops

      def save_id_with_type(id, type, mode=Solis::Store::SaveMode::PRE_DELETE_PEERS_IF_DIFF_SET)

        s, p, o = [id, 'has_type', type]

        op = {
          "type" => "save_id_with_type",
          "mode" => mode,
          "content" => [s, p, o]
        }

        puts op

        @ops << op

      end

      def save_attribute_for_id(id, name_attr, val_attr, type_attr, mode=Solis::Store::SaveMode::PRE_DELETE_PEERS_IF_DIFF_SET)

        s, p, o, dto = [id, name_attr, val_attr, type_attr]

        op = {
          "type" => "save_attribute_for_id",
          "mode" => mode,
          "content" => [s, p, o, dto]
        }

        puts op

        @ops << op

      end

      def delete_attribute_for_id(id, name_attr)

        s, p = [id, name_attr]

        op = {
          "type" => "delete_attribute_for_id",
          "mode" => Solis::Store::DeleteMode::DELETE_ATTRIBUTE,
          "content" => [s, p]
        }

        puts op

        @ops << op

      end


    end

  end
end