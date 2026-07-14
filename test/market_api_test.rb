# frozen_string_literal: true

require_relative "test_helper"
require "zero_x_da/market_client_bot/market_api"

class MarketAPITest < Minitest::Test
  class StubbedMarketAPI < ZeroXDA::MarketClientBot::MarketAPI
    attr_reader :attempts, :backoffs

    def initialize(outcomes:, **options)
      @outcomes = outcomes
      @attempts = 0
      @backoffs = []
      super(**options, sleeper: ->(seconds) { @backoffs << seconds })
    end

    private

    def perform_http_request(_uri, _request)
      @attempts += 1
      outcome = @outcomes.fetch(@attempts - 1)
      raise outcome if outcome.is_a?(Exception)

      outcome
    end
  end

  def test_retries_a_cold_start_timeout
    api = api_with(Timeout::Error.new("cold start"), json_response)

    assert_equal({ "status" => "ok" }, api.health)
    assert_equal 2, api.attempts
    assert_equal [2], api.backoffs
  end

  def test_loads_products_from_the_authenticated_catalog_endpoint
    payload = '{"data":[{"id":"ton","attributes":{"name":"TON"}}]}'
    api = api_with(response("200", payload))

    assert_equal "ton", api.products.first.fetch("id")
    assert_equal 1, api.attempts
  end

  def test_retries_gateway_errors
    %w[502 503 504].each do |status|
      api = api_with(response(status, "<html>starting</html>"), json_response)

      assert_equal({ "status" => "ok" }, api.health)
      assert_equal 2, api.attempts
    end
  end

  def test_retries_a_temporary_non_json_response
    api = api_with(response("200", "<html>starting</html>"), json_response)

    assert_equal({ "status" => "ok" }, api.health)
    assert_equal 2, api.attempts
  end

  def test_uses_exponential_backoff_until_the_market_recovers
    failures = Array.new(5) { Timeout::Error.new("cold start") }
    api = api_with(*failures, json_response)

    assert_equal({ "status" => "ok" }, api.health)
    assert_equal [2, 4, 8, 16, 30], api.backoffs
  end

  def test_wraps_the_error_after_retry_is_exhausted
    api = api_with(*Array.new(6) { Timeout::Error.new("cold start") })

    error = assert_raises(ZeroXDA::MarketClientBot::MarketAPI::Error) { api.health }

    assert_includes error.message, "cold start"
    assert_equal 6, api.attempts
  end

  private

  def api_with(*outcomes)
    StubbedMarketAPI.new(
      outcomes: outcomes,
      base_url: "https://market.example",
      token: "token"
    )
  end

  def json_response
    response("200", '{"status":"ok"}')
  end

  def response(status, body)
    response_class = {
      "200" => Net::HTTPOK,
      "502" => Net::HTTPBadGateway,
      "503" => Net::HTTPServiceUnavailable,
      "504" => Net::HTTPGatewayTimeout
    }.fetch(status)
    value = response_class.new("1.1", status, "response")
    value.instance_variable_set(:@read, true)
    value.instance_variable_set(:@body, body)
    value
  end
end
