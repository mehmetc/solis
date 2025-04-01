module Solis
  class Store
    class Memory
      def initialize
        @store = RDF::Repository.new
      end
    end
  end
end