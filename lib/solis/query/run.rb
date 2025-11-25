require 'solis/store/sparql/client'
require 'solis/query/result_transformer'
require 'solis/config_file'

class Solis::Query::Runner
  def self.run(entity, query, options = {})
    sparql_client = Solis::Store::Sparql::Client.new(
      Solis::Options.instance.get[:sparql_endpoint],
      graph_name: graph_name
    )

    raw_result = sparql_client.query(query, options)
    model = options[:model] || nil

    transform_result(raw_result, entity, model)
  rescue StandardError => e
    puts e.message
    raise e
  end

  private

  def self.transform_result(raw_result, entity, model)
    if raw_result.is_a?(SPARQL::Client)
      frame_and_transform(raw_result, entity, model)
    else
      transform_select_results(raw_result, model)
    end
  end

  def self.frame_and_transform(sparql_result, entity, model)
    graph = build_graph_from_result(sparql_result)
    context = build_context(entity)

    framed = nil
    JSON::LD::API.fromRDF(graph) do |expanded|
      framed = JSON::LD::API.frame(expanded, context)
    end

    Solis::Query::ResultTransformer.new(model).transform(framed)
  end

  def self.transform_select_results(raw_result, model)
    results = raw_result.map(&:to_h)
    Solis::Query::ResultTransformer.new(model).transform({'@graph' => results})
  end

  def self.build_graph_from_result(sparql_result)
    graph = RDF::Graph.new
    sparql_result.query('select * where{?s ?p ?o}').each do |statement|
      graph << [statement.s, statement.p, statement.o]
    end
    graph
  end

  def self.build_context(entity)
    JSON.parse(%(
{
  "@context": {
    "@vocab": "#{graph_name}",
    "id": "@id"
  },
  "@type": "#{entity}",
  "@embed": "@always"
}
    ))
  end

  def self.graph_name
    graphs = Solis::Options.instance.get[:graphs]
    raise Solis::Error::NotFoundError, 'No graph name found' if graphs.nil?

    graphs.find { |g| g['type'].eql?(:main) }&.fetch('name') || ''
  end
end