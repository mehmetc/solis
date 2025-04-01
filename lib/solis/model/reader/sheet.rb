require_relative 'sheet/simple_sheets'
require 'data_collector/config_file'
require 'linkeddata'

module Solis
  class Model
    class Reader
      class Sheet
        def self.read(key, spreadsheet_id, options = {})
          data = nil

          DataCollector::ConfigFile.path = options[:config_path] if options[:config_path]
          cache_dir = DataCollector::ConfigFile.include?(:cache) ? DataCollector::ConfigFile[:cache] : '/tmp'

          if ::File.exist?("#{cache_dir}/#{spreadsheet_id}.json") && (options.include?(:from_cache) && options[:from_cache])
            Solis.logger.info("from cache #{cache_dir}/#{spreadsheet_id}.json")
            data = JSON.parse(::File.read("#{cache_dir}/#{spreadsheet_id}.json"), { symbolize_names: true })
            return data
          else
            Solis.logger.info("from source #{spreadsheet_id}")
            session = SimpleSheets.new(key, spreadsheet_id)
            session.key = key
            sheets = {}
            session.worksheets.each do |worksheet|
              sheet = ::Sheet.new(worksheet)
              sheets[sheet.title] = sheet
            end

            validate(sheets)
          end
          sheets
        end

        def self.validate(sheets)
          prefixes = sheets['_PREFIXES']
          metadata = sheets['_METADATA']

          raise "_PREFIXES tab must have ['base', 'prefix', 'uri'] as a header at row 1" unless (%w[base prefix uri] - prefixes.header).length == 0
          raise '_PREFIXES.base can only have one base URI' if prefixes.map { |m| m['base'] }.grep(/\*/).count != 1

          raise "_METADATA tab must have ['key', 'value'] as a header at row 1" unless (%w[key value] - metadata.header).length == 0

          if sheets.key?('_ENTITIES')
            entities = sheets['_ENTITIES']
            raise "_ENTITIES tab must have ['name', 'nameplural', 'description', 'subclassof', 'sameas'] as a header at row 1" unless (%w[name nameplural description subclassof sameas] - entities.header).length == 0

            entities.each do |entity|
              raise "Plural not found for #{entity['name']}" if entity['nameplural'].nil? || entity['nameplural'].empty?
            end
          end

          if sheets.key?('_REFERENCES')
            references = sheets['_REFERENCES']
            raise "_REFERENCES tab must have ['sheeturl', 'description', 'entityrange'] as a header at row 1" unless (%w[sheeturl description entityrange] - references.header).length == 0
          end
        end

        def self.to_shacl(sheets)
          prefixes = {}
          sheets['_PREFIXES'].each do |e|
            prefixes.store(e['prefix'].to_sym, { uri: e['uri'], base: e['base'].eql?('*') })
          end

          graph = RDF::Graph.new

          pp prefixes

        end
      end
    end
  end
end