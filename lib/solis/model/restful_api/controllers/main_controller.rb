# frozen_string_literal: true
require 'http'
require_relative 'generic_controller'
require_relative '../../entity'

class MainController < GenericController

  post '/:entities' do

    content_type :json

    data = JSON.parse(request.body.read)
    data = data['attributes'] if data.include?('attributes')

    type_plural = params['entities']
    type = settings.model.find_entity_by_plural(type_plural)

    entity = Solis::Model::Entity.new(data, settings.model, type, settings.store)

    entity.save

    result = entity.get_internal_data

    result.to_json

  rescue StandardError => e
    content_type :json
    halt 500, api_error(request.url, e)
  end



  put '/:entities/:id' do

    content_type :json

    data = JSON.parse(request.body.read)
    data = data['attributes'] if data.include?('attributes')
    data_patch = data

    type_plural = params['entities']
    type = settings.model.find_entity_by_plural(type_plural)

    id = params['id']
    uri_id = "#{settings.model.namespace}#{id}"

    data = {
      '_id' => uri_id
    }

    entity = Solis::Model::Entity.new(data, settings.model, type, settings.store)

    entity.load(deep = true)

    entity.patch(data_patch, opts={
      add_missing_refs: true,
      autoload_missing_refs: true
    })

    entity.save

    result = entity.get_internal_data

    result.to_json

  # rescue StandardError => e
  #   content_type :json
  #   halt 500, api_error(request.url, e)
  end



  delete '/:entity/:id' do

    type_plural = params['entities']
    type = settings.model.find_entity_by_plural(type_plural)

    id = params['id']
    uri_id = "#{settings.model.namespace}#{id}"

    data = {
      '_id' => uri_id
    }

    entity = Solis::Model::Entity.new(data, settings.model, type, settings.store)

    result = entity.get_internal_data

    entity.destroy

    result.to_json

  rescue StandardError => e
    content_type :json
    halt 500, api_error(request.url, e)
  end



  get '/:entities/:id' do

    content_type :json

    type_plural = params['entities']
    type = settings.model.find_entity_by_plural(type_plural)

    id = params['id']
    uri_id = "#{settings.model.namespace}#{id}"

    data = {
      '_id' => uri_id
    }

    entity = Solis::Model::Entity.new(data, settings.model, type, settings.store)

    entity.load(deep = true)

    result = entity.get_internal_data

    result.to_json

  rescue StandardError => e
    content_type :json
    halt 500, api_error(request.url, e)
  end

end
