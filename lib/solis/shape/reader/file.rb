require 'linkeddata'

module Solis
  module Shape
    module Reader
      class File
        def self.read(filename, options = {})
          @filename = ::File.expand_path(filename)
          raise "File not found #{@filename}" unless ::File.exist?(@filename)

          RDF::Graph.load(@filename, **options)
        end
      end
    end
  end
end
