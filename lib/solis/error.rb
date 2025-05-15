module Solis
  module Error
    class General < StandardError
    end

    class MissingParameter < General
    end

    class BadParameter < General
    end

    class NotFound < General
    end

    class PropertyNotFound < General
    end
  end
end