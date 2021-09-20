Dir.glob("#{File.dirname(__FILE__)}/error/**.rb") do |dir|
  require dir
end