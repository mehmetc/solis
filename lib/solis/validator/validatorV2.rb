
# NOTE:
# This validator does not support:
# - sh:flags

require 'shacl'
require 'open3'
require 'rdf/turtle'
require 'json/ld'
require 'json'
require 'fileutils'

module Solis
  class SHACLValidatorV2

    class DockerPullError < StandardError
    end

    class DockerContainerBinExecError < StandardError
    end

    class PossibleBadlyFormedSHACLError < StandardError
    end

    def initialize(shacl, format, opts={})
      # make graph shacl
      if format.eql?(:ttl)
        graph_shacl = RDF::Graph.new
        graph_shacl.from_ttl(shacl)
      elsif format.eql?(:graph)
        graph_shacl = shacl
      end
      @graph_shacl = graph_shacl
      # pull last validator docker image
      @url_image_docker = "ghcr.io/ashleycaselli/shacl:latest"
      str_cmd = "docker image pull #{@url_image_docker}"
      stdout, stderr, status = Open3.capture3(str_cmd)
      unless status.success?
        raise DockerPullError, stderr
      end
      # make config for validator files
      @path_dir = opts[:path_dir] || Dir.home
      @name_file_graph_shacl = "graph_shacl.ttl"
      @name_file_graph_data = "graph_data.ttl"
    end

    def execute(data, format)
      # make graph data
      graph_data = nil
      if format.eql?(:jsonld)
        graph_data = RDF::Graph.new << JSON::LD::API.toRdf(data)
      elsif format.eql?(:graph)
        graph_data = data
      end
      # make and fill data dir
      path_dir_data = make_and_fill_data_dir(@graph_shacl, graph_data)
      # call validation bin in docker container
      str_cmd = "docker run --rm -v #{path_dir_data}:/data #{@url_image_docker} validate -datafile /data/#{@name_file_graph_data} -shapesfile /data/#{@name_file_graph_shacl}"
      stdout, stderr, status = Open3.capture3(str_cmd)
      unless status.success?
        unless stdout.include?('sh:ValidationReport')
          raise DockerContainerBinExecError, stdout
        end
      end
      conform = status.success?
      # remove warnings on top
      i_start = stdout.index("PREFIX")
      str_ttl = stdout[i_start..]
      # parse validation results
      graph = RDF::Graph.new << RDF::Turtle::Reader.new(str_ttl)
      context = {
        "sh" => "http://www.w3.org/ns/shacl#"
      }
      compacted = nil
      JSON::LD::API::fromRdf(graph) do |expanded|
        compacted = JSON::LD::API.compact(expanded, context)
      end
      messages = []
      compacted['@graph'].each do |o|
        next if o['@type'].eql?('sh:ValidationReport')
        message = "#{o['sh:focusNode']['@id']}, #{o.dig('sh:resultPath', '@id')}, #{o['sh:resultMessage']}"
        messages << message
      end unless compacted['@graph'].nil?
      # NOTE: if shape file is badly formed, the following can happen:
      # - despite conform, there are still messages
      # - these messages are about bad shapes, and ay not contain o['sh:resultPath']['@id'],
      # that is why dig() above.
      if conform and messages.size > 0
        raise PossibleBadlyFormedSHACLError
      end
      # destroy dir data
      destroy_data_dir(path_dir_data)
      # return
      [conform, messages]
    end

    private

    def make_and_fill_data_dir(graph_shacl, graph_data)
      # crate cross-platform UTC datetime string (ISO8601-compatible preferably): YYYYMMDDTHHMMSSssZ
      str_dt = Time.now.utc.strftime("%Y%m%dT%H%M%S%2NZ")
      # make dir
      path_dir_data = File.join(@path_dir, str_dt)
      Dir.mkdir(path_dir_data)
      # dump graph data to file
      path_file_graph_data = File.join(path_dir_data, @name_file_graph_data)
      File.open(path_file_graph_data, "w") do |file|
        # NOTE: disable validation of dumped triples, this has to happen later from the validator
        file.puts(graph_data.dump(:ntriples, validate: false))
      end
      # dump shacl data to file
      path_file_graph_shacl = File.join(path_dir_data, @name_file_graph_shacl)
      File.open(path_file_graph_shacl, "w") do |file|
        file.puts(graph_shacl.dump(:ntriples))
      end
      path_dir_data
    end

    def destroy_data_dir(path_dir_data)
      FileUtils.remove_dir(path_dir_data,true)
    end

  end
end