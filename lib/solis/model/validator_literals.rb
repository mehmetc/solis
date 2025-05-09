
require 'iso8601'
require 'edtf'

# hash of datatype/regex: lambda validator.
# Hashes can be easily merged, so they can come from different sources.
# First the specific string key is searched, otherwise a regex.
# "str_value" is the literal value to validate.
# "hv" is the hash itself, so that if synonyms need to be tested,
# the synonym validator can be called as hv[<key_synonym>].call(hv, value).

module Solis
  class Model
    module Literals
      def self.get_default_hash_validator
        {

          "http://www.w3.org/2006/time#DateTimeInterval" => lambda do |hv, str_value|
            begin
              ISO8601::TimeInterval.parse(str_value)
              true
            rescue
              false
            end
          end,

          /https:\/\/www.loc.gov\/standards\/datetime\// => lambda do |hv, str_value|
            begin
              v = EDTF.parse(str_value)
              if v.nil?
                raise StandardError
              end
              true
            rescue
              false
            end
          end,

        }
      end
    end
  end
end