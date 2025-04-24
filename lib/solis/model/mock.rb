
require_relative "../validator/validatorV1"
require_relative "../validator/validatorV2"


module Solis
  class ModelMock

    attr_reader :shapes, :validator, :namespace

    def initialize(params = {})
      @graph = params[:graph]
      @parser = SHACLParser.new(@graph)
      @shapes = @parser.parse_shapes
      @validator = Solis::SHACLValidatorV2.new(@graph, :graph, {
        path_dir: params[:tmp_dir]
      })
      @prefix = params[:prefix]
      @namespace = params[:namespace]
    end

  end
end
