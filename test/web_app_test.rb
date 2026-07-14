require_relative "test_helper"
require "json"
require "rack/mock"
require "zero_x_da/market_client_bot/web_app"

class WebAppTest < Minitest::Test
  class ImmediateDispatcher
    def call(&task)
      task.call
    end
  end

  class HoldingDispatcher
    attr_reader :task

    def call(&task)
      @task = task
    end
  end

  class Handler
    attr_reader :updates

    def initialize
      @updates = []
    end

    def handle(update)
      @updates << update
    end
  end

  def setup
    @handler = Handler.new
    @client = Rack::MockRequest.new(
      ZeroXDA::MarketClientBot::WebApp.new(
        bot: @handler,
        webhook_secret: "webhook-secret",
        dispatcher: ImmediateDispatcher.new
      )
    )
  end

  def test_health_is_public_and_includes_server_time
    response = @client.get("/health")

    assert_equal 200, response.status
    document = JSON.parse(response.body)
    assert_equal "ok", document.fetch("status")
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, document.fetch("server_time"))
  end

  def test_rejects_a_webhook_without_the_telegram_secret
    response = @client.post(
      "/telegram/webhook",
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(update_id: 1)
    )

    assert_equal 401, response.status
    assert_empty @handler.updates
  end

  def test_accepts_and_dispatches_a_verified_webhook
    response = @client.post(
      "/telegram/webhook",
      "HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN" => "webhook-secret",
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(update_id: 1, message: { text: "/start" })
    )

    assert_equal 200, response.status
    assert_equal 1, @handler.updates.first.fetch("update_id")
  end

  def test_acknowledges_the_webhook_before_processing_the_update
    dispatcher = HoldingDispatcher.new
    client = Rack::MockRequest.new(
      ZeroXDA::MarketClientBot::WebApp.new(
        bot: @handler,
        webhook_secret: "webhook-secret",
        dispatcher: dispatcher
      )
    )

    response = client.post(
      "/telegram/webhook",
      "HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN" => "webhook-secret",
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(update_id: 2, message: { text: "/start" })
    )

    assert_equal 200, response.status
    assert_empty @handler.updates

    dispatcher.task.call
    assert_equal 2, @handler.updates.first.fetch("update_id")
  end
end
