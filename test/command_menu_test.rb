# frozen_string_literal: true

require_relative "test_helper"
require "zero_x_da/market_client_bot/bot"
require "zero_x_da/market_client_bot/command_menu"

class CommandMenuTest < Minitest::Test
  CommandMenu = ZeroXDA::MarketClientBot::CommandMenu

  def test_unauthorized_menu_uses_authorization_icon
    assert_equal [
      { command: "start", description: "🔐 авторизація" }
    ], CommandMenu.start(locale: "uk_UA")
  end

  def test_ukrainian_admin_menu_uses_icons_and_expected_order
    menu = CommandMenu.admin(locale: "uk_UA")

    assert_equal %w[
      buy status apply_prices apply_price rates set_rate users servers setadmin
    ], menu.map { |item| item.fetch(:command) }
    assert_equal [
      "🛍️ купити",
      "👤 власний статус",
      "📦 застосувати ціни",
      "💰 встановити ціну продукту",
      "💱 курси валют відносно USDT",
      "⚙️ встановити курс валюти",
      "👥 активні користувачі",
      "📊 стан серверів",
      "🔑 призначити адміністратора"
    ], menu.map { |item| item.fetch(:description) }
  end

  def test_unknown_locale_falls_back_to_english_with_icons
    descriptions = CommandMenu.admin(locale: "fr_FR").to_h do |item|
      [item.fetch(:command), item.fetch(:description)]
    end

    assert_equal "📦 apply prices", descriptions.fetch("apply_prices")
    assert_equal "⚙️ set exchange rate", descriptions.fetch("set_rate")
  end

  def test_client_menu_does_not_include_admin_commands
    menu = CommandMenu.client(locale: "uk_UA")

    assert_equal %w[buy status], menu.map { |item| item.fetch(:command) }
    assert_equal ["🛍️ купити", "👤 власний статус"], menu.map { |item| item.fetch(:description) }
  end

  def test_telegram_language_is_used_when_core_user_has_no_persisted_locale
    market = FakeMarketAPI.new
    telegram = FakeTelegramAPI.new
    bot = build_bot(market: market, telegram: telegram)

    bot.handle(update(command: "/status", language_code: "uk", message_id: 77))

    descriptions = command_descriptions(telegram)
    assert_equal "📦 застосувати ціни", descriptions.fetch("apply_prices")
    assert_equal "⚙️ встановити курс валюти", descriptions.fetch("set_rate")
  end

  def test_persisted_locale_has_priority_over_telegram_language
    market = Class.new(FakeMarketAPI) do
      def authenticate_telegram(user:, chat:)
        super.tap { |entry| entry.fetch("attributes")["locale"] = "en_US" }
      end
    end.new
    telegram = FakeTelegramAPI.new
    bot = build_bot(market: market, telegram: telegram)

    bot.handle(update(command: "/status", language_code: "uk", message_id: 78))

    descriptions = command_descriptions(telegram)
    assert_equal "📦 apply prices", descriptions.fetch("apply_prices")
    assert_equal "⚙️ set exchange rate", descriptions.fetch("set_rate")
  end

  def test_status_deletes_user_command_and_bot_status_message
    telegram = FakeTelegramAPI.new
    bot = build_bot(telegram: telegram)

    bot.handle(update(command: "/status", message_id: 501))

    assert_includes telegram.deleted_messages, { chat_id: 990, message_id: 501 }
    assert_includes telegram.deleted_messages, { chat_id: 990, message_id: 1 }
  end

  def test_each_admin_command_deletes_the_incoming_command
    CommandMenu::ADMIN_COMMANDS.each_with_index do |name, index|
      telegram = FakeTelegramAPI.new
      bot = build_bot(telegram: telegram)
      message_id = 600 + index

      bot.handle(update(command: "/#{name}", message_id: message_id))

      assert_includes telegram.deleted_messages, { chat_id: 990, message_id: message_id }, name.to_s
    end
  end

  def test_regular_client_command_is_not_deleted
    telegram = FakeTelegramAPI.new
    bot = build_bot(telegram: telegram)

    bot.handle(update(command: "/buy", message_id: 700))

    refute_includes telegram.deleted_messages, { chat_id: 990, message_id: 700 }
  end

  private

  def build_bot(market: FakeMarketAPI.new, telegram:, status_message_ttl: 0)
    ZeroXDA::MarketClientBot::Bot.new(
      market_api: market,
      telegram_api: telegram,
      status_message_ttl: status_message_ttl
    )
  end

  def update(command:, language_code: "uk", message_id:)
    {
      "message" => {
        "message_id" => message_id,
        "text" => command,
        "from" => {
          "id" => 99,
          "username" => "zero",
          "first_name" => "Sasha",
          "language_code" => language_code
        },
        "chat" => { "id" => 990, "type" => "private" }
      }
    }
  end

  def command_descriptions(telegram)
    telegram.command_sets.last.fetch(:commands).to_h do |item|
      [item.fetch(:command), item.fetch(:description)]
    end
  end
end
