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
    assert_equal %w[buy status], commands.fetch(:commands).map { |item| item.fetch(:command) }
    assert_equal [{ chat_id: 770, message_id: 1 }], @telegram.deleted_messages
  end

  def test_status_displays_the_current_user_state
    @bot.handle(update("/status"))

    text = @telegram.messages.last.fetch(:text)
    assert_includes text, "Роль: client"
    assert_includes text, "status: active ✅"
    assert_equal 0, @market.health_requests
  end

  def test_authorized_client_can_open_the_nine_product_buy_catalog
    @bot.handle(update("/buy"))

    message = @telegram.messages.last
    assert_equal "обери продукт для купівлі:", message.fetch(:text)
    rows = message.dig(:reply_markup, :inline_keyboard)
    assert_equal [3, 3, 3], rows.map(&:length)
    buttons = rows.flatten
    assert_equal "buy_premium_3m", buttons.first.fetch(:callback_data)
    assert_equal "buy_eth", buttons.last.fetch(:callback_data)
    assert_equal 1, @market.product_requests
    assert_equal ["uk_UA"], @market.product_locales
  end

  def test_buy_callback_reauthenticates_the_client_and_acknowledges_selection
    @bot.handle(callback("buy_stars_1000"))

    assert_equal 1, @market.requests.length
    assert_equal 1, @market.product_requests
    assert_equal(
      {
        callback_query_id: "callback-1",
        text: "обрано: Stars 1000"
      },
      @telegram.answered_callbacks.last
    )
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
    assert_includes text, "✅ Market core"
    assert_includes text, "12.07.2026 · 00:00:00 UTC"
    assert_includes text, "✅ Client bot"
    assert_includes text, "12.07.2026 · 00:00:01 UTC"
  end

  def test_non_admin_cannot_see_or_execute_servers
    @bot.handle(update("/servers"))

    assert_equal "доступ заборонено.", @telegram.messages.last.fetch(:text)
    assert_equal 0, @market.health_requests
    assert_equal %w[buy status], @telegram.command_sets.last.fetch(:commands).map { |item| item.fetch(:command) }
  end

  def test_admin_can_list_active_users
    @bot.handle(update("/users", user_id: 99, chat_id: 990))

    text = @telegram.messages.first.fetch(:text)
    assert_includes text, "👥 Активні користувачі: 1"
    assert_includes text, "👤 @zero"
    refute_includes text, "12345678-1234-4000-8000-123456789012"
    assert_includes text, "Роль: client"
  end

  def test_non_admin_cannot_list_active_users
    @bot.handle(update("/users", user_id: 88))

    assert_equal "доступ заборонено.", @telegram.messages.first.fetch(:text)
  end

  def test_admin_menu_contains_work_commands_then_fixed_footer
    @bot.handle(update("/start", user_id: 99, chat_id: 990))

    command_set = @telegram.command_sets.last
    assert_equal({ type: "chat", chat_id: 990 }, command_set.fetch(:scope))
    commands = command_set.fetch(:commands).map { |item| item.fetch(:command) }
    assert_equal %w[buy apply_prices apply_price rates set_rate status servers users setadmin], commands
    assert_equal %w[status servers users setadmin], commands.last(4)
  end

  def test_admin_promotes_a_user_and_installs_their_admin_menu
    @bot.handle(update("/setadmin @target_user", user_id: 99, chat_id: 990))

    request = @market.requests.last
    assert_equal 99, request.fetch(:actor_telegram_user_id)
    assert_equal "@target_user", request.fetch(:target)
    command_set = @telegram.command_sets.last
    assert_equal({ type: "chat", chat_id: "880" }, command_set.fetch(:scope))
    assert_includes command_set.fetch(:commands).map { |item| item.fetch(:command) }, "setadmin"
    assert_includes @telegram.messages.last.fetch(:text), "Вам призначено роль admin"
  end

  def test_non_admin_cannot_execute_a_manually_typed_setadmin_command
    @bot.handle(update("/setadmin 88", user_id: 77, chat_id: 770))

    assert_equal "доступ заборонено.", @telegram.messages.last.fetch(:text)
    refute @market.requests.any? { |request| request.key?(:actor_telegram_user_id) }
    command_set = @telegram.command_sets.last
    assert_equal %w[buy status], command_set.fetch(:commands).map { |item| item.fetch(:command) }
  end

  def test_admin_receives_the_price_application_form
    @bot.handle(update("/apply_prices", user_id: 99, chat_id: 990))

    assert_equal(
      [{ actor_telegram_user_id: 99, locale: "uk_UA" }],
      @market.price_proposal_requests
    )
    text = @telegram.messages.last.fetch(:text)
    assert_includes text, "📦 Застосування цін"
    assert_includes text, "💵 USDT"
    assert_includes text, "1. Telegram Premium 3 міс. · premium_3m"
    assert_includes text, "⏮ 7.20 → 💰 7.45 USDT"
    assert_includes text, "✏️ @zero"
    assert_includes text, "/apply_price <sku|позиція|назва> <сума>"
  end

  def test_price_application_falls_back_to_en_us
    @bot.handle(update("/apply_prices", user_id: 99, chat_id: 990, language_code: "fr"))

    assert_equal "fr_FR", @market.price_proposal_requests.last.fetch(:locale)
    text = @telegram.messages.last.fetch(:text)
    assert_includes text, "📦 Application des prix"
    assert_includes text, "1. Telegram Premium 3 months · premium_3m"
  end

  def test_non_admin_cannot_request_the_price_application_form
    @bot.handle(update("/apply_prices"))

    assert_equal "доступ заборонено.", @telegram.messages.last.fetch(:text)
    assert_empty @market.price_proposal_requests
  end

  def test_admin_applies_a_single_price_by_sku
    @bot.handle(update("/apply_price premium_6m 7.45", user_id: 99, chat_id: 990))

    assert_equal(
      [{ actor_telegram_user_id: 99, prices: [{ sku: "premium_6m", amount_usdt: "7.45" }] }],
      @market.applied_prices
    )
    text = @telegram.messages.last.fetch(:text)
    assert_includes text, "price applied ✅"
    assert_includes text, "Telegram Premium 6 міс. (premium_6m)"
    assert_includes text, "7.45 USDT"
  end

  def test_admin_applies_a_single_price_by_catalog_position
    @bot.handle(update("/apply_price 5 3.10", user_id: 99, chat_id: 990))

    price = @market.applied_prices.last.fetch(:prices).first
    assert_equal "stars_1000", price.fetch(:sku)
    assert_equal "3.10", price.fetch(:amount_usdt)
  end

  def test_admin_applies_a_single_price_by_database_short_name
    @bot.handle(update("/apply_price Premium 6m 7.45", user_id: 99, chat_id: 990))

    price = @market.applied_prices.last.fetch(:prices).first
    assert_equal "premium_6m", price.fetch(:sku)
    assert_equal "7.45", price.fetch(:amount_usdt)
  end

  def test_apply_price_without_an_amount_asks_for_the_amount
    @bot.handle(update("/apply_price premium_6m", user_id: 99, chat_id: 990))

    assert_includes @telegram.messages.last.fetch(:text), "введи нову ціну для Telegram Premium 6 міс."
    assert_empty @market.applied_prices

    @bot.handle(update("7.45", user_id: 99, chat_id: 990))

    assert_equal(
      [{ actor_telegram_user_id: 99, prices: [{ sku: "premium_6m", amount_usdt: "7.45" }] }],
      @market.applied_prices
    )
    assert_includes @telegram.messages.last.fetch(:text), "price applied ✅"
  end

  def test_apply_price_without_arguments_walks_through_product_and_amount
    @bot.handle(update("/apply_price", user_id: 99, chat_id: 990))

    message = @telegram.messages.last
    assert_equal "обери продукт для оновлення ціни:", message.fetch(:text)
    buttons = message.dig(:reply_markup, :inline_keyboard).flatten
    assert_equal "applyprice_premium_3m", buttons.first.fetch(:callback_data)
    assert_equal "applyprice_eth", buttons.last.fetch(:callback_data)

    @bot.handle(callback("applyprice_stars_1000", user_id: 99, chat_id: 990))

    assert_equal "обрано: Stars 1000", @telegram.answered_callbacks.last.fetch(:text)
    assert_includes @telegram.messages.last.fetch(:text), "введи нову ціну для Stars 1000"
    assert_empty @market.applied_prices

    @bot.handle(update("3.10", user_id: 99, chat_id: 990))

    price = @market.applied_prices.last.fetch(:prices).first
    assert_equal "stars_1000", price.fetch(:sku)
    assert_equal "3.10", price.fetch(:amount_usdt)
  end

  def test_apply_price_with_a_malformed_amount_asks_for_the_amount
    @bot.handle(update("/apply_price premium_6m abc", user_id: 99, chat_id: 990))

    texts = @telegram.messages.map { |item| item.fetch(:text) }
    assert_includes texts, "некоректна сума. введи число, наприклад 7.45"
    assert_includes texts.last, "введи нову ціну для Telegram Premium 6 міс."
    assert_empty @market.applied_prices

    @bot.handle(update("abc", user_id: 99, chat_id: 990))

    assert_includes @telegram.messages.last.fetch(:text), "некоректна сума"
    assert_empty @market.applied_prices

    @bot.handle(update("7.45", user_id: 99, chat_id: 990))

    price = @market.applied_prices.last.fetch(:prices).first
    assert_equal "premium_6m", price.fetch(:sku)
    assert_equal "7.45", price.fetch(:amount_usdt)
  end

  def test_apply_price_dialog_accepts_a_typed_product_after_an_unknown_reference
    @bot.handle(update("/apply_price premium 7.45", user_id: 99, chat_id: 990))

    texts = @telegram.messages.map { |item| item.fetch(:text) }
    assert(texts.any? { |text| text.include?("продукт не знайдено: premium") })
    assert_equal "обери продукт для оновлення ціни:", texts.last
    assert_empty @market.applied_prices

    @bot.handle(update("premium_6m", user_id: 99, chat_id: 990))

    assert_includes @telegram.messages.last.fetch(:text), "введи нову ціну для Telegram Premium 6 міс."

    @bot.handle(update("7.45", user_id: 99, chat_id: 990))

    price = @market.applied_prices.last.fetch(:prices).first
    assert_equal "premium_6m", price.fetch(:sku)
    assert_equal "7.45", price.fetch(:amount_usdt)
  end

  def test_a_new_command_cancels_a_pending_price_dialog
    @bot.handle(update("/apply_price premium_6m", user_id: 99, chat_id: 990))
    @bot.handle(update("/status", user_id: 99, chat_id: 990))
    @bot.handle(update("7.45", user_id: 99, chat_id: 990))

    assert_empty @market.applied_prices
  end

  def test_non_admin_cannot_apply_a_price
    @bot.handle(update("/apply_price premium_6m 7.45"))

    assert_equal "доступ заборонено.", @telegram.messages.last.fetch(:text)
    assert_empty @market.applied_prices
  end

  def test_admin_can_list_fx_rates
    @bot.handle(update("/rates", user_id: 99, chat_id: 990))

    assert_equal 1, @market.fx_rate_requests
    text = @telegram.messages.last.fetch(:text)
    assert_includes text, "💱 Курси валют"
    assert_includes text, "1 USDT = 1 USDT"
    assert_includes text, "1 EUR = 1.16 USDT"
    assert_includes text, "/set_rate"
  end

  def test_admin_sets_an_fx_rate_with_uppercased_currency
    @bot.handle(update("/set_rate eur 1.16", user_id: 99, chat_id: 990))

    assert_equal(
      [{ actor_telegram_user_id: 99, rates: [{ currency: "EUR", usdt_per_unit: "1.16" }] }],
      @market.applied_fx_rates
    )
    text = @telegram.messages.last.fetch(:text)
    assert_includes text, "rate applied ✅"
    assert_includes text, "1 EUR = 1.16 USDT"
  end

  def test_set_rate_with_malformed_arguments_shows_usage
    @bot.handle(update("/set_rate EUR abc", user_id: 99, chat_id: 990))

    assert_includes @telegram.messages.last.fetch(:text), "format: /set_rate"
    assert_empty @market.applied_fx_rates

    @bot.handle(update("/set_rate", user_id: 99, chat_id: 990))

    assert_includes @telegram.messages.last.fetch(:text), "format: /set_rate"
    assert_empty @market.applied_fx_rates
  end

  def test_non_admin_cannot_manage_fx_rates
    @bot.handle(update("/rates"))

    assert_equal "доступ заборонено.", @telegram.messages.last.fetch(:text)
    assert_equal 0, @market.fx_rate_requests

    @bot.handle(update("/set_rate EUR 1.16"))

    assert_equal "доступ заборонено.", @telegram.messages.last.fetch(:text)
    assert_empty @market.applied_fx_rates
  end

  def test_ignores_unknown_messages
    @bot.handle(update("100 stars"))

    assert_empty @market.requests
    assert_empty @telegram.messages
  end

  def test_accepts_command_with_bot_username
    @bot.handle(update("/servers@zeroxda_market_client_bot", user_id: 99, chat_id: 990))

    assert_includes @telegram.messages.first.fetch(:text), "✅ Market core"
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

    assert_equal "Сервер запускається…", @telegram.messages.first.fetch(:text)
    assert_includes @telegram.messages.last.fetch(:text), "авторизація успішна"
  end

  private

  def update(text, user_id: 77, chat_id: 770, language_code: "uk")
    {
      "message" => {
        "text" => text,
        "from" => {
          "id" => user_id,
          "username" => "zero",
          "first_name" => "Sasha",
          "language_code" => language_code
        },
        "chat" => { "id" => chat_id, "type" => "private" }
      }
    }
  end

  def callback(data, user_id: 77, chat_id: 770)
    {
      "callback_query" => {
        "id" => "callback-1",
        "data" => data,
        "from" => {
          "id" => user_id,
          "username" => "zero",
          "first_name" => "Sasha",
          "language_code" => "uk"
        },
        "message" => {
          "chat" => { "id" => chat_id, "type" => "private" }
        }
      }
    }
  end
end
