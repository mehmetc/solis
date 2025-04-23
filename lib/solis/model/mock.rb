
require_relative "../validator"


module Solis
  class ModelMock

    attr_reader :shapes, :validator, :namespace

    def initialize(params = {})
      @graph = params[:graph]
      @parser = SHACLParser.new(@graph)
      @shapes = @parser.parse_shapes
      @validator = Solis::SHACLValidator.new(@graph, :graph)
      @prefix = params[:prefix]
      @namespace = params[:namespace]
    end

  end
end
