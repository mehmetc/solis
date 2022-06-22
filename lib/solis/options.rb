module Solis
  class Options
    @instance = new
    private_class_method :new

    def self.instance
      @instance
    end

    def set=(options)
      @options = options
      @options
    end

    def get
      @options || {}
    end
  end
end