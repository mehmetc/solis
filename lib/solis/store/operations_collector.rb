

require 'securerandom'
require_relative 'common'


module Solis
  class Store

    module OperationsCollector
      # Expects:
      # - @ops
      # - @logger

      def save_id_with_type(id, type, mode=Solis::Store::SaveMode::PRE_DELETE_PEERS_IF_DIFF_SET)

        op = {
          "id" => SecureRandom.uuid,
          "name" => "save_id_with_type",
          "type" => "write",
          "opts" => mode,
          "content" => [id, 'has_type', type]
        }

        @logger.debug(op)

        @ops << op

        op['id']

      end

      def save_attribute_for_id(id, name_attr, val_attr, type_attr, mode=Solis::Store::SaveMode::PRE_DELETE_PEERS_IF_DIFF_SET)

        op = {
          "id" => SecureRandom.uuid,
          "name" => "save_attribute_for_id",
          "type" => "write",
          "opts" => mode,
          "content" => [id, name_attr, val_attr, type_attr]
        }

        @logger.debug(op)

        @ops << op

        op['id']

      end

      def delete_attribute_for_id(id, name_attr)

        op = {
          "id" => SecureRandom.uuid,
          "name" => "delete_attribute_for_id",
          "type" => "write",
          "opts" => Solis::Store::DeleteMode::DELETE_ATTRIBUTE,
          "content" => [id, name_attr]
        }

        @logger.debug(op)

        @ops << op

        op['id']

      end

      def get_data_for_id(id, namespace, deep=false)

        mode = deep ? Solis::Store::GetMode::DEEP : Solis::Store::GetMode::SHALLOW

        op = {
          "id" => SecureRandom.uuid,
          "name" => "get_data_for_id",
          "type" => "read",
          "opts" => mode,
          "content" => [id, namespace]
        }

        @logger.debug(op)

        @ops << op

        op['id']

      end

      def ask_if_id_is_referenced(id)

        op = {
          "id" => SecureRandom.uuid,
          "name" => "ask_if_id_is_referenced",
          "type" => "read",
          "opts" => nil,
          "content" => [id]
        }

        @logger.debug(op)

        @ops << op

        op['id']

      end

      def ask_if_id_exists(id)

        op = {
          "id" => SecureRandom.uuid,
          "name" => "ask_if_id_exists",
          "type" => "read",
          "opts" => nil,
          "content" => [id]
        }

        @logger.debug(op)

        @ops << op

        op['id']

      end

      def delete_attributes_for_id(id)

        op = {
          "id" => SecureRandom.uuid,
          "name" => "delete_attributes_for_id",
          "type" => "write",
          "opts" => nil,
          "content" => [id]
        }

        @logger.debug(op)

        @ops << op

        op['id']

      end


    end

  end
end