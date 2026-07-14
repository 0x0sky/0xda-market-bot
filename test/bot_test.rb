require_relative "test_helper"
require "zero_x_da/market_client_bot/bot"

class BotTest < Minitest::Test
  def setup
    @market = FakeMarketAPI.new
    @telegram = FakeTelegramAPI.new
    @bot = ZeroXDA::MarketClientBot::Bot.new(
      market_api: @market,
      telegram_api: @telegram,
      clock: -> { Time.utc(2026, 7, 12, 0, 0, 1) },
      status_message_ttl: 0
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
    assert_equal <<~TEXT.strip, @telegram.messages.first.fetch(:text)
      авторизація успішна ✅
      role: client
      status: active ✅
    TEXT
    commands = @telegram.command_sets.first
    assert_equal({ type: "chat", chat_id: 770 }, commands.fetch(:scope))
    assert_equal %w[status], commands.fetch(:commands).map { |item| item.fetch(:command) }
    assert_equal [{ chat_id: 770, message_id: 1 }], @telegram.deleted_messages
  end

  def test_status_displays_the_current_user_state
    @bot.handle(update("/status"))

    text = @telegram.messages.last.fetch(:text)
    assert_includes text, "role: client"
    assert_includes text, "status: active ✅"
    assert_equal 0, @market.health_requests
  end

  def test_status_uses_the_client_context_for_a_broker_identity
    market = Class.new(FakeMarketAPI) do
      def authenticate_telegram(**arguments)
        super.tap { |user| user.fetch("attributes")["role"] = "broker" }
      end
    end.new
    bot = ZeroXDA::MarketClientBot::Bot.new(
      market_api: market,
      telegram_api: @telegram
    )

    bot.handle(update("/status"))

    text = @telegram.messages.last.fetch(:text)
    assert_includes text, "role: client"
    refute_includes text, "role: broker"
  end

  def test_admin_servers_displays_both_services_and_server_times
    @bot.handle(update("/servers", user_id: 99, chat_id: 990))

    text = @telegram.messages.first.fetch(:text)
    assert_includes text, "market core: ok ✅"
    assert_includes text, "core time: 2026-07-12T00:00:00.000000Z"
    assert_includes text, "client bot: ok ✅"
    assert_includes text, "bot time: 2026-07-12T00:00:01.000000Z"
  end

  def test_non_admin_cannot_see_or_execute_servers
    @bot.handle(update("/servers"))

    assert_equal "доступ заборонено.", @telegram.messages.last.fetch(:text)
    assert_equal 0, @market.health_requests
    assert_equal %w[status], @telegram.command_sets.last.fetch(:commands).map { |item| item.fetch(:command) }
  end

  def test_admin_can_list_active_users
    @bot.handle(update("/users", user_id: 99, chat_id: 990))

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

  def test_admin_menu_contains_only_admin_scoped_commands
    @bot.handle(update("/start", user_id: 99, chat_id: 990))

    command_set = @telegram.command_sets.last
    assert_equal({ type: "chat", chat_id: 990 }, command_set.fetch(:scope))
    commands = command_set.fetch(:commands).map do |item|
      item.fetch(:command)
    end
    assert_equal %w[status servers users setadmin], commands
  end

  def test_admin_promotes_a_user_and_installs_their_admin_menu
    @bot.handle(update("/setadmin @target_user", user_id: 99, chat_id: 990))

    request = @market.requests.last
    assert_equal 99, request.fetch(:actor_telegram_user_id)
    assert_equal "@target_user", request.fetch(:target)
    command_set = @telegram.command_sets.last
    assert_equal({ type: "chat", chat_id: "880" }, command_set.fetch(:scope))
    assert_includes command_set.fetch(:commands).map { |item| item.fetch(:command) }, "setadmin"
    assert_includes @telegram.messages.last.fetch(:text), "admin призначений"
  end

  def test_non_admin_cannot_execute_a_manually_typed_setadmin_command
    @bot.handle(update("/setadmin 88", user_id: 77, chat_id: 770))

    assert_equal "доступ заборонено.", @telegram.messages.last.fetch(:text)
    refute @market.requests.any? { |request| request.key?(:actor_telegram_user_id) }
    command_set = @telegram.command_sets.last
    assert_equal %w[status], command_set.fetch(:commands).map { |item| item.fetch(:command) }
  end

  def test_ignores_unknown_messages
    @bot.handle(update("100 stars"))

    assert_empty @market.requests
    assert_empty @telegram.messages
  end

  def test_accepts_command_with_bot_username
    @bot.handle(update("/servers@zeroxda_market_client_bot", user_id: 99, chat_id: 990))

    assert_includes @telegram.messages.first.fetch(:text), "market core: ok"
  end

  def test_reports_a_slow_market_start_and_sends_the_result_later
    slow_market = Class.new(FakeMarketAPI) do
      def authenticate_telegram(**arguments)
        sleep 0.03
        super
      end
    end.new
    bot = ZeroXDA::MarketClientBot::Bot.new(
      market_api: slow_market,
      telegram_api: @telegram,
      server_start_notice_delay: 0.005
    )

    bot.handle(update("/start"))

    assert_equal "0xda-market запускається…", @telegram.messages.first.fetch(:text)
    assert_includes @telegram.messages.last.fetch(:text), "авторизація успішна"
  end

  private

  def update(text, user_id: 77, chat_id: 770)
    {
      "message" => {
        "text" => text,
        "from" => {
          "id" => user_id,
          "username" => "zero",
          "first_name" => "Sasha",
          "language_code" => "uk"
        },
        "chat" => { "id" => chat_id, "type" => "private" }
      }
    }
  end
end
