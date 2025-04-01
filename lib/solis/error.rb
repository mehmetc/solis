module Solis
  module Error
    class General < StandardError
    end

    class MissingParameter < StandardError
    end

    class BadParameter < StandardError
    end

    class NotFound < General
    end
  end
end