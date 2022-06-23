require "test_helper"

class QueryTest < Minitest::Test
  def setup
    #    Solis::ConfigFile.path = './test/resources'
    @solis = Solis::Graph.new(Solis::Shape::Reader::File.read(Solis::ConfigFile[:solis][:shacl]), Solis::ConfigFile[:solis])
    build_data(@solis)
  end

  def test_multiple_filters
    #//boekenplanken?page[number]=0&page[size]=5&include=werk,formaat&filter[agent_id][eq]=10004&filter[formaat_id][eq]=338ebd71-19ad-5820-8a03-48e1cc8d971c

    # params = {"page"=>{"number"=>"0", "size"=>"5"},
    #           "include"=>"werk,formaat",
    #           "filter"=>
    #             {"agent_id"=>{"eq"=>"10004"},
    #              "formaat_id"=>{"eq"=>"338ebd71-19ad-5820-8a03-48e1cc8d971c"}},
    #           "entity"=>"boekenplanken",
    #           "stats"=>{"total"=>:count}}

    params = {"page"=>{"number"=>"0", "size"=>"5"},
              "include"=>"teacher,students",
              "filter"=>
                {"teacher_id"=>{"eq"=>"3"},
                 "course_id"=>{"eq"=>"8"}},
              "entity"=>"schedule",
              "stats"=>{"total"=>:count}}


    s = ScheduleResource.all(params)
    puts s.to_jsonapi

  end

end