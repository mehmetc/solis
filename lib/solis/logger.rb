require 'data_collector/core'

module Solis
    def self.logger(*destinations)
      @logger ||= DataCollector::Core.logger(destinations.flatten)
    end
end