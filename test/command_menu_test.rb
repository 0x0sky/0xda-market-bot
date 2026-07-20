# frozen_string_literal: true

require_relative "test_helper"
require "zero_x_da/market_client_bot/bot"
require "zero_x_da/market_client_bot/command_menu"

class CommandMenuTest < Minitest::Test
  CommandMenu = ZeroXDA::MarketClientBot::CommandMenu

  def test_ukrainian_admin_menu_has_no_english_descriptions
    descriptions = CommandMenu.admin(locale: "uk_UA").to_h do |item|
      [item.fetch(:command), item.fetch(:description)]
    end

    assert_equal "застосувати ціни", descriptions.fetch("apply_prices")
    assert_equal "встановити ціну продукту", descriptions.fetch("apply_price")
    assert_equal "курси валют відносно USDT", descriptions.fetch("rates")
    assert_equal "встановити курс валюти", descriptions.fetch("set_rate")
  end

  def test_unknown_locale_falls_back_to_english
    descriptions = CommandMenu.admin(locale: "fr_FR").to_h do |item|
      [item.fetch(:command), item.fetch(:description)]
    end

    assert_equal "apply prices", descriptions.fetch("apply_prices")
    assert_equal "set exchange rate", descriptions.fetch("set_rate")
  end

  def test_client_menu_does_not_include_admin_commands
    commands = CommandMenu.client(locale: "uk_UA").map { |item| item.fetch(:command) }

    assert_equal %w[buy status], commands
  end

  def test_bot_syncs_ukrainian_admin_menu_from_persisted_locale
    market = FakeMarketAPI.new
    telegram = FakeTelegramAPI.new
    bot = ZeroXDA::MarketClientBot::Bot.new(
      market_api: market,
      telegram_api: telegram,
      status_message_ttl: 0
    )
    market.define_singleton_method(:authenticate_telegram) do |user:, chat:|
      {
        "id" => "admin-id",
        "attributes" => { "role" => "admin", "status" => "active", "locale" => "uk_UA" }
      }
    end

    bot.handle(
      "message" => {
        "text" => "/status",
        "from" => { "id" => 99, "language_code" => "uk" },
        "chat" => { "id" => 990, "type" => "private" }
      }
    )

    descriptions = telegram.command_sets.last.fetch(:commands).to_h do |item|
      [item.fetch(:command), item.fetch(:description)]
    end
    assert_equal "застосувати ціни", descriptions.fetch("apply_prices")
    assert_equal "встановити курс валюти", descriptions.fetch("set_rate")
  end
end
