# frozen_string_literal: true

require_relative "test_helper"
require "zero_x_da/market_client_bot/bot"
require "zero_x_da/market_client_bot/command_menu"

class CommandMenuTest < Minitest::Test
  CommandMenu = ZeroXDA::MarketClientBot::CommandMenu

  def test_ukrainian_admin_menu_has_icons_and_no_english_descriptions
    descriptions = CommandMenu.admin(locale: "uk_UA").to_h do |item|
      [item.fetch(:command), item.fetch(:description)]
    end

    assert_equal "📦 застосувати ціни", descriptions.fetch("apply_prices")
    assert_equal "💰 встановити ціну продукту", descriptions.fetch("apply_price")
    assert_equal "💱 курси валют відносно USDT", descriptions.fetch("rates")
    assert_equal "⚙️ встановити курс валюти", descriptions.fetch("set_rate")
    assert_equal "👥 активні користувачі", descriptions.fetch("users")
    assert_equal "📊 стан серверів", descriptions.fetch("servers")
    assert_equal "🔑 призначити адміністратора", descriptions.fetch("setadmin")
  end

  def test_unknown_locale_falls_back_to_english_with_icons
    descriptions = CommandMenu.admin(locale: "fr_FR").to_h do |item|
      [item.fetch(:command), item.fetch(:description)]
    end

    assert_equal "📦 apply prices", descriptions.fetch("apply_prices")
    assert_equal "⚙️ set exchange rate", descriptions.fetch("set_rate")
  end

  def test_start_menu_uses_authorization_icon
    assert_equal(
      [{ command: "start", description: "🔐 авторизація" }],
      CommandMenu.start(locale: "uk_UA")
    )
  end

  def test_client_menu_has_only_client_commands_with_icons
    commands = CommandMenu.client(locale: "uk_UA")

    assert_equal %w[buy status], commands.map { |item| item.fetch(:command) }
    assert_equal ["🛍️ купити", "👤 власний статус"], commands.map { |item| item.fetch(:description) }
  end

  def test_admin_menu_keeps_client_commands_first_and_admin_actions_below
    commands = CommandMenu.admin(locale: "uk_UA").map { |item| item.fetch(:command) }

    assert_equal(
      %w[buy status apply_prices apply_price rates set_rate users servers setadmin],
      commands
    )
  end

  def test_telegram_language_is_used_when_core_user_has_no_persisted_locale
    market = FakeMarketAPI.new
    telegram = FakeTelegramAPI.new
    bot = ZeroXDA::MarketClientBot::Bot.new(
      market_api: market,
      telegram_api: telegram,
      status_message_ttl: 0
    )

    bot.handle(update(language_code: "uk"))

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
    bot = ZeroXDA::MarketClientBot::Bot.new(
      market_api: market,
      telegram_api: telegram,
      status_message_ttl: 0
    )

    bot.handle(update(language_code: "uk"))

    descriptions = command_descriptions(telegram)
    assert_equal "📦 apply prices", descriptions.fetch("apply_prices")
    assert_equal "⚙️ set exchange rate", descriptions.fetch("set_rate")
  end

  private

  def update(language_code:)
    {
      "message" => {
        "text" => "/status",
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
