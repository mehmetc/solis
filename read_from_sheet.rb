#$LOAD_PATH << '.' << './lib'
require 'bundler'
Bundler.require

require 'solis'
require 'config_file'

sheet_key = :t
key=ConfigFile[:key]
sheets = {abv: ConfigFile[:abv], t:i ConfigFile[:t] , lp: ConfigFile[:lp]}
s = Solis::Shape::Reader::Sheet.read(key, sheets[sheet_key])

File.open("./data/#{sheet_key.to_s}.sql", 'wb') {|f| f.puts s[:sql]}
File.open("./data/#{sheet_key.to_s}.json", 'wb') {|f| f.puts s[:inflections]}
File.open("./data/#{sheet_key.to_s}_shacl.ttl", 'wb') {|f| f.puts s[:shacl]}
File.open("./data/#{sheet_key.to_s}_schema.ttl", 'wb') {|f| f.puts s[:schema]}
File.open("./data/#{sheet_key.to_s}.puml", 'wb') {|f| f.puts s[:plantuml]}
File.open("./data/#{sheet_key.to_s}_erd.puml", 'wb') {|f| f.puts s[:plantuml_erd]}

