require_relative "test_helper"
require "zero_x_da/market_client_bot/bot"

class BotTest < Minitest::Test
  def setup
    @market = FakeMarketAPI.new
    @telegram = FakeTelegramAPI.new
    @bot = ZeroXDA::MarketClientBot::Bot.new(
      market_api: @market,
      telegram_api: @telegram
    )
  end

  def test_start_authenticates_the_telegram_user_and_confirms_authorization
    @bot.handle(update("/start"))

    assert_equal 1, @market.requests.length
    request = @market.requests.first
    assert_equal 77, request.dig(:user, "id")
    assert_equal 770, request.dig(:chat, "id")
    assert_equal 770, @telegram.messages.first.fetch(:chat_id)
    assert_includes @telegram.messages.first.fetch(:text), "авторизація успішна"
    assert_includes @telegram.messages.first.fetch(:text), "role: client"
    assert_includes @telegram.messages.first.fetch(:text), "user: 12345678"
  end

  def test_ignores_messages_other_than_start
    @bot.handle(update("100 stars"))

    assert_empty @market.requests
    assert_empty @telegram.messages
  end

  def test_accepts_start_command_with_bot_username
    @bot.handle(update("/start@zeroxda_market_client_bot"))

    assert_equal 1, @market.requests.length
  end

  private

  def update(text)
    {
      "message" => {
        "text" => text,
        "from" => {
          "id" => 77,
          "username" => "zero",
          "first_name" => "Sasha",
          "language_code" => "uk"
        },
        "chat" => { "id" => 770, "type" => "private" }
      }
    }
  end
end
