# frozen_string_literal: true

require_relative "test_helper"
require "zero_x_da/market_client_bot/market_api"

class MarketAPITest < Minitest::Test
  class StubbedMarketAPI < ZeroXDA::MarketClientBot::MarketAPI
    attr_reader :attempts

    def initialize(failures:, **options)
      super(**options)
      @failures = failures
      @attempts = 0
    end

    private

    def perform_http_request(_uri, _request)
      @attempts += 1
      raise Timeout::Error, "cold start" if @attempts <= @failures

      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.instance_variable_set(:@body, '{"status":"ok"}')
      response
    end
  end

  def test_retries_a_cold_start_timeout
    api = StubbedMarketAPI.new(
      failures: 1,
      base_url: "https://market.example",
      token: "token"
    )

    assert_equal({ "status" => "ok" }, api.health)
    assert_equal 2, api.attempts
    assert_operator ZeroXDA::MarketClientBot::MarketAPI::READ_TIMEOUT, :>=, 60
  end

  def test_wraps_the_error_after_retry_is_exhausted
    api = StubbedMarketAPI.new(
      failures: 2,
      base_url: "https://market.example",
      token: "token"
    )

    error = assert_raises(ZeroXDA::MarketClientBot::MarketAPI::Error) { api.health }

    assert_includes error.message, "cold start"
    assert_equal 2, api.attempts
  end
end
