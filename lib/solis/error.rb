module Solis
  module Error
    class General < StandardError
      def http_status
        503
      end
    end

    class MissingParameter < General
      def http_status
        400
      end
    end

    class BadParameter < General
      def http_status
        400
      end
    end

    class NotFound < General
      def http_status
        404
      end
    end

    class PropertyNotFound < General
      def http_status
        400
      end
    end

    class NotAllowed < General
      def http_status
        403
      end
    end

    class ValidationFailed < General
      def http_status
        503
      end
    end
  end
end