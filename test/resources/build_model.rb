$LOAD_PATH << '.' << './lib'
require 'solis'

key = ENV['GDRIVE_KEY']# Solis::ConfigFile[:key]
Solis::ConfigFile.path='test/resources'
s = Solis::Shape::Reader::Sheet.read(key, Solis::ConfigFile[:sheets][:t], from_cache: false)

puts Dir.getwd

File.open('./test/resources/data/t_shacl.ttl', 'wb') {|f| f.puts s[:shacl]}
File.open('./test/resources/data/t.json', 'wb') {|f| f.puts s[:inflections]}
File.open('./test/resources/data/t_schema.ttl', 'wb') {|f| f.puts s[:schema]}
File.open('./test/resources/data/t.puml', 'wb') {|f| f.puts s[:plantuml]}
File.open('./test/resources/data/t.json_schema', 'wb') {|f| f.puts s[:json_schema]}
#File.open('./data/t.sql', 'wb') {|f| f.puts s[:sql]}

# `plantuml -tsvg ./data/t.puml`
# `gm convert ./data/t.svg ./data/t.png`
