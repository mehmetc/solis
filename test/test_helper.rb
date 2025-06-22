# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "solis"
require "solis/model/writer"
require "solis/validator/validatorV1"
require "solis/validator/validatorV2"
require "solis/utils/jsonld"
require "solis/utils/json"
require "solis/utils/rdf"
require "solis/model/entity"
require "solis/store/rdf_proxy"
require "solis/mock/sparql_client"
require "http"

require "minitest/autorun"


def make_api_controller_class_thread_friendly(class_controller)
  Class.new(class_controller) do
    set :url_base, 'http://127.0.0.1:4567'
    set :url_ping, 'http://127.0.0.1:4567/ping'
    set :url_exit, 'http://127.0.0.1:4567/exit'
    set :threaded, true
    get "/ping" do
      "pong"
    end
    get "/exit" do
      self.class.quit!
    end
  end
end

def block_until_alive(url_ping)
  while true
    begin
      response = HTTP.get(url_ping)
      break
    rescue
      # puts 'failed ... retry'
      next
    end
  end
end
