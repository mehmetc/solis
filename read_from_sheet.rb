#$LOAD_PATH << '.' << './lib'
require 'bundler'
Bundler.require

require 'solis'

sheet_key = :t
key=Solis::ConfigFile[:key]
sheets = {abv: Solis::ConfigFile[:sheets][:abv], t: Solis::ConfigFile[:sheets][:t] , lp: Solis::ConfigFile[:sheets][:lp]}
s = Solis::Shape::Reader::Sheet.read(key, sheets[sheet_key], from_cache: false)

File.open("./data/#{sheet_key.to_s}.sql", 'wb') {|f| f.puts s[:sql]}
File.open("./data/#{sheet_key.to_s}.json", 'wb') {|f| f.puts s[:inflections]}
File.open("./data/#{sheet_key.to_s}_shacl.ttl", 'wb') {|f| f.puts s[:shacl]}
File.open("./data/#{sheet_key.to_s}_schema.ttl", 'wb') {|f| f.puts s[:schema]}
File.open("./data/#{sheet_key.to_s}.puml", 'wb') {|f| f.puts s[:plantuml]}
File.open("./data/#{sheet_key.to_s}_erd.puml", 'wb') {|f| f.puts s[:plantuml_erd]}

%x{java -jar ~/Downloads/plantuml.jar -tsvg ./data/#{sheet_key.to_s}.puml}
%x{gm convert ./data/#{sheet_key.to_s}.svg ./data/#{sheet_key.to_s}.png}
%x{java -jar ~/Downloads/plantuml.jar -tsvg ./data/#{sheet_key.to_s}_erd.puml}
%x{gm convert ./data/#{sheet_key.to_s}_erd.svg ./data/#{sheet_key.to_s}_erd.png}
