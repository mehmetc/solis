Dir.glob("#{File.dirname(__FILE__)}/store/*.rb").each do |file|
  require file
end