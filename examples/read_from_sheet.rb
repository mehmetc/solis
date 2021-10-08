# $LOAD_PATH << '.' << './lib'
require 'bundler'
Bundler.require

require 'solis'
Solis::ConfigFile.path = Dir.pwd
sheet_key = :t
key = Solis::ConfigFile[:key]
s = Solis::Shape::Reader::Sheet.read(key, Solis::ConfigFile[:sheets][sheet_key], from_cache: false)

File.open("./data/#{sheet_key}.sql", 'wb') { |f| f.puts s[:sql] }
File.open("./data/#{sheet_key}.json", 'wb') { |f| f.puts s[:inflections] }
File.open("./data/#{sheet_key}_shacl.ttl", 'wb') { |f| f.puts s[:shacl] }
File.open("./data/#{sheet_key}_schema.ttl", 'wb') { |f| f.puts s[:schema] }
File.open("./data/#{sheet_key}.puml", 'wb') { |f| f.puts s[:plantuml] }
File.open("./data/#{sheet_key}_erd.puml", 'wb') { |f| f.puts s[:plantuml_erd] }

#`java -jar ~/Downloads/plantuml.jar -tsvg ./data/#{sheet_key}.puml`
#`gm convert ./data/#{sheet_key}.svg ./data/#{sheet_key}.png`
#`java -jar ~/Downloads/plantuml.jar -tsvg ./data/#{sheet_key}_erd.puml`
#`gm convert ./data/#{sheet_key}_erd.svg ./data/#{sheet_key}_erd.png`
