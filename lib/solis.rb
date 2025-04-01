# frozen_string_literal: true

require_relative "solis/version"
require_relative 'solis/error'
require_relative 'solis/logger'
require_relative 'solis/model'
require_relative 'solis/store'

module Solis
  def self.new(*params)
    params_hash = params.reduce({}) {|h,pairs| pairs.each {|k,v| h[k] = v}; h}
    Solis::Model.new(params_hash)
  end

end
