# frozen_string_literal: true

require_relative "solis/version"
require_relative 'solis/config'
require_relative 'solis/error'
require_relative 'solis/logger'
require_relative 'solis/model'
require_relative 'solis/store'

module Solis
  def self.new(*params)
    params_hash = params.reduce({}) {|h,pairs| pairs.each {|k,v| h[k] = v}; h}
    raise Solis::Error::BadParameter, "Please provide a {store: Solis::Store::Memory.new()}" unless params_hash[:store]

    solis = Class.new do
      attr_accessor :store, :model
      def initialize(params)
        @store = params[:store]
        @model = Solis::Model.new(params)
      end
    end.new(params_hash)
  end
end
