require_relative "test_helper"
require "zero_x_da/market_client_bot/bot"

class BotTest < Minitest::Test
  def setup
    @market = FakeMarketAPI.new
    @telegram = FakeTelegramAPI.new
    @bot = ZeroXDA::MarketClientBot::Bot.new(
      market_api: @market,
      telegram_api: @telegram,
      admin_telegram_ids: [77],
      clock: -> { Time.utc(2026, 7, 12, 0, 0, 1) }
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

  def test_status_displays_both_services_and_server_times
    @bot.handle(update("/status"))

    text = @telegram.messages.first.fetch(:text)
    assert_includes text, "market core: ok ✅"
    assert_includes text, "core time: 2026-07-12T00:00:00.000000Z"
    assert_includes text, "client bot: ok ✅"
    assert_includes text, "bot time: 2026-07-12T00:00:01.000000Z"
  end

  def test_admin_can_list_active_users
    @bot.handle(update("/users"))

    text = @telegram.messages.first.fetch(:text)
    assert_includes text, "active users: 1"
    assert_includes text, "telegram: 77"
    assert_includes text, "uuid: 12345678-1234-4000-8000-123456789012"
    assert_includes text, "role: client"
  end

  def test_non_admin_cannot_list_active_users
    @bot.handle(update("/users", user_id: 88))

    assert_equal "доступ заборонено.", @telegram.messages.first.fetch(:text)
  end

  def test_ignores_unknown_messages
    @bot.handle(update("100 stars"))

    assert_empty @market.requests
    assert_empty @telegram.messages
  end

  def test_accepts_command_with_bot_username
    @bot.handle(update("/status@zeroxda_market_client_bot"))

    assert_includes @telegram.messages.first.fetch(:text), "market core: ok"
  end

  private

  def update(text, user_id: 77)
    {
      "message" => {
        "text" => text,
        "from" => {
          "id" => user_id,
          "username" => "zero",
          "first_name" => "Sasha",
          "language_code" => "uk"
        },
        "chat" => { "id" => 770, "type" => "private" }
      }
    }
  end
end
