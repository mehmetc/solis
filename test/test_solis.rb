# frozen_string_literal: true

require "test_helper"

class TestSolis < Minitest::Test
  def setup
    super
  end
  def test_does_it_have_a_version
    refute_nil ::Solis::VERSION
  end

  def test_mandatory_parameters
    assert_raises Solis::Error::BadParameter do
      solis = Solis.new(not_mandatory: '1234')
    end
    # missing Google key
    assert_raises Solis::Error::BadParameter do
      solis = Solis.new(uri: 'google+sheet://18JDgCfr2CLl_jATuvFTcpu-a5T6CWAgJwTwEqtSe8YE', config_path: 'test/resources/incorrect')
    end
  end

  def test_setup_logger
    #define logers
    s = StringIO.new
    logger = Solis.logger([STDOUT, s])
    assert_kind_of(Logger, logger)

    logger.info('test')

    s.rewind
    assert_match(/test/, s.string)
  end
end
