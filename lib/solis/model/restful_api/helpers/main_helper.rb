
require 'json'


module Sinatra
  module MainHelper

    def api_error(source, e)

      content_type :json

      stacktrace = ""
      stacktrace = e.backtrace.join("\n") unless e.nil?

      message = {
        'error' => {
          'source' => source,
          'message' => e.message,
          'class' => e.class.name,
          'stacktrace' => stacktrace
        }
      }.to_json
    end

  end

  helpers MainHelper

end