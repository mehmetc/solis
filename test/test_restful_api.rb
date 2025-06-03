require 'test_helper'

class TestRESTfulAPI < Minitest::Test

  def setup
    @namespace = 'https://example.com/'
    @prefix = 'example'

    @repository = RDF::Repository.new
    store = Solis::Store::RDFProxy.new(@repository, @namespace)

    dir_tmp = File.join(__dir__, './data')

    config = {
      store: store,
      model: {
        prefix: @prefix,
        namespace: @namespace,
        uri: "file://test/resources/car/car_test_entity_save.ttl",
        content_type: 'text/turtle',
        tmp_dir: dir_tmp,
        plurals: {
          'Car' => 'cars',
          'Person' => 'persons',
          'Address' => 'addresses'
        }
      }
    }

    @solis = Solis.new(config)

    api = @solis.model.generate_restful_api
    @api = make_api_controller_class_thread_friendly(api)

  end

  def test_api_smooth_up_and_down

    app_thread = Thread.new do
      @api.run!
    end

    caller_thread = Thread.new do
      block_until_alive(@api.url_ping)
      begin
        # nothing
      ensure
        HTTP.get(@api.url_exit)
      end
    end

    [app_thread, caller_thread].each(&:join)

  end

  def test_api_post

    app_thread = Thread.new do
      @api.run!
    end

    caller_thread = Thread.new do
      block_until_alive(@api.url_ping)
      begin

        @repository.clear!

        data = JSON.parse %(
          {
            "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
            "color": ["green", "yellow"],
            "brand": "toyota",
            "owners": [
              {
                "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
                "name": "jon doe",
                "address": {
                  "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
                  "street": "fake street"
                }
              }
            ]
          }
        )

        response = HTTP.post("#{@api.url_base}/cars", :json => data)
        assert_equal(response.status, 200)
        data_res = response.parse
        assert_equal(data_res['_id'], data['_id'])

      ensure
        HTTP.get(@api.url_exit)
      end
    end

    [app_thread, caller_thread].each(&:join)

  end

  def test_api_get

    app_thread = Thread.new do
      @api.run!
    end

    caller_thread = Thread.new do
      block_until_alive(@api.url_ping)
      begin

        @repository.clear!

        data = JSON.parse %(
          {
            "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
            "color": ["green", "yellow"],
            "brand": "toyota",
            "owners": [
              {
                "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
                "name": "jon doe",
                "address": {
                  "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
                  "street": "fake street"
                }
              }
            ]
          }
        )

        response = HTTP.post("#{@api.url_base}/cars", :json => data)
        assert_equal(response.status, 200)

        response = HTTP.get("#{@api.url_base}/addresses/3117582b-cdef-4795-992f-b62efd8bb1ea")
        assert_equal(response.status, 200)
        data_res = response.parse
        assert_equal(data_res['_id'], 'https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea')

      ensure
        HTTP.get(@api.url_exit)
      end
    end

    [app_thread, caller_thread].each(&:join)

  end

  def test_api_put

    app_thread = Thread.new do
      @api.run!
    end

    caller_thread = Thread.new do
      block_until_alive(@api.url_ping)
      begin

        @repository.clear!

        data = JSON.parse %(
          {
            "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
            "color": ["green", "yellow"],
            "brand": "toyota",
            "owners": [
              {
                "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
                "name": "jon doe",
                "address": {
                  "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
                  "street": "fake street"
                }
              }
            ]
          }
        )

        response = HTTP.post("#{@api.url_base}/cars", :json => data)
        assert_equal(response.status, 200)

        data_patch = JSON.parse %(
          {
            "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
            "color": "pink"
          }
        )

        response = HTTP.put("#{@api.url_base}/cars/93b8781d-50de-47e2-a1dc-33cb641fd4be", :json => data_patch)
        assert_equal(response.status, 200)
        data_res = response.parse
        assert_equal(data_res['_id'], 'https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be')
        assert_equal(data_res['color'], 'pink')

      ensure
        HTTP.get(@api.url_exit)
      end
    end

    [app_thread, caller_thread].each(&:join)

  end

end

def test_api_delete

  app_thread = Thread.new do
    @api.run!
  end

  caller_thread = Thread.new do
    block_until_alive(@api.url_ping)
    begin

      @repository.clear!

      data = JSON.parse %(
          {
            "_id": "https://example.com/93b8781d-50de-47e2-a1dc-33cb641fd4be",
            "color": ["green", "yellow"],
            "brand": "toyota",
            "owners": [
              {
                "_id": "https://example.com/dfd736c6-db76-44ed-b626-cdcec59b69f9",
                "name": "jon doe",
                "address": {
                  "_id": "https://example.com/3117582b-cdef-4795-992f-b62efd8bb1ea",
                  "street": "fake street"
                }
              }
            ]
          }
        )

      response = HTTP.post("#{@api.url_base}/cars", :json => data)
      assert_equal(response.status, 200)

      response = HTTP.delete("#{@api.url_base}/cars/93b8781d-50de-47e2-a1dc-33cb641fd4be")
      assert_equal(response.status, 200)
      data_res = response.parse
      assert_equal(data_res.empty?, true)

    ensure
      HTTP.get(@api.url_exit)
    end
  end

  [app_thread, caller_thread].each(&:join)

end
