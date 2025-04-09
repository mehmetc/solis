module Solis
  class Model
    class Writer
      class Generic
        def initialize
          super
        end

        def self.write(data, options = {})
          Solis.logger.error('To be implemented')
        end
      end
    end
  end
end