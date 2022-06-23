# $LOAD_PATH << '.' << './lib'
require 'bundler'
Bundler.require

require 'solis'
require 'pp'
require 'json'

Solis::ConfigFile.path = './'
g = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis][:env])

model = g.shape_as_model('Codetabel')
resource = g.shape_as_resource('Codetabel')
# model.model_template.to_json
#
data = %( {
  "type": "agenten",
  "id": 1776,
  "attributes": {
    "identificatie": [
      {
        "id": 1776,
        "waarde": 1776
      }
    ],
    "type": {
      "id": "292r3yzt3rv7owo7"
    },
    "naam": [
      {
        "waarde": "Bond Moyson-gewest Tielt",
        "type_naam": {
          "id": "p9qirbgec6a0j8ri7qst"
        }
      }
    ],
    "datering": "1970-01-01",
    "geschiedenis_agent": [
      ""
    ],
    "functie_beroep_activiteit": {},
    "erkenning": {
      "id": "4cvras56mmdqmay715kns7"
    },
    "adres": {},
    "telefoon": "",
    "email": "",
    "website": "",
    "gebouw": "",
    "zoektoegang": {},
    "openingsuren": "",
    "toegang_gebruiksvoorwaarden": "",
    "bereikbaarheid": {},
    "taal": {},
    "associaties": {},
    "bron_beschrijving_agent": {},
    "bibliografie_agent": {},
    "opmerking": ""
  }
}
)

begin
  s = resource.find({label: 'persoon'})
  j = JSON.parse(s.to_jsonapi)
  puts JSON.pretty_generate(j)

  #Agent = g.shape_as_model('Agent')
  agent_data = JSON.parse(data)['attributes']
  pp agent_data
  agent = Agent.new(agent_data)

  begin
    agent.save
  rescue StandardError => e
    puts e.message
  end


rescue Graphiti::Errors::RecordNotFound
  puts "record not found"
end


