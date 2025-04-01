module Solis
  class Store
    class Triple
      def initialize
        @store = RDF::Repository.new
      end
    end
  end
end