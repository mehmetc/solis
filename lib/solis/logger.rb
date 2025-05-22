require 'data_collector/core'
module Solis
    def self.logger(*destinations)
      @logger if @logger && (@log_destination.eql?(destinations.flatten) || destinations.empty? || destinations.nil?)
      @log_destination = destinations.flatten
      @logger = DataCollector::Core.logger(@log_destination)
    end
end