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

  def test_admin_menu_keeps_four_footer_commands_last
    menu = CommandMenu.admin(locale: "uk_UA")

    assert_equal %w[
      buy apply_prices apply_price rates set_rate status servers users setadmin
    ], menu.map { |item| item.fetch(:command) }
    assert_equal %w[status servers users setadmin], menu.last(4).map { |item| item.fetch(:command) }
    assert_equal [
      "👤 власний статус",
      "📊 стан серверів",
      "👥 активні користувачі",
      "🔑 призначити адміністратора"
    ], menu.last(4).map { |item| item.fetch(:description) }
  end

  def test_unknown_locale_falls_back_to_english
    descriptions = CommandMenu.admin(locale: "fr_FR").to_h do |item|
      [item.fetch(:command), item.fetch(:description)]
    end

    assert_equal "📦 apply prices", descriptions.fetch("apply_prices")
    assert_equal "⚙️ set exchange rate", descriptions.fetch("set_rate")
  end

  def test_client_menu_keeps_buy_and_status
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

  def test_servers_and_users_delete_command_and_bot_responses
    %w[servers users].each_with_index do |name, index|
      telegram = FakeTelegramAPI.new
      bot = build_bot(telegram: telegram)
      message_id = 600 + index

      bot.handle(update(command: "/#{name}", message_id: message_id))

      assert_includes telegram.deleted_messages, { chat_id: 990, message_id: message_id }, name
      telegram.messages.each do |message|
        assert_includes(
          telegram.deleted_messages,
          { chat_id: message.fetch(:chat_id), message_id: message.fetch("message_id") },
          name
        )
      end
    end
  end

  def test_other_commands_are_not_deleted
    %w[status setadmin apply_prices apply_price rates set_rate buy].each_with_index do |name, index|
      telegram = FakeTelegramAPI.new
      bot = build_bot(telegram: telegram)
      message_id = 700 + index

      bot.handle(update(command: command_for(name), message_id: message_id))

      refute_includes telegram.deleted_messages, { chat_id: 990, message_id: message_id }, name
    end
  end

  private

  def build_bot(market: FakeMarketAPI.new, telegram:, status_message_ttl: 0)
    ZeroXDA::MarketClientBot::Bot.new(
      market_api: market,
      telegram_api: telegram,
      status_message_ttl: status_message_ttl
    )
  end

  def command_for(name)
    case name
    when "setadmin" then "/setadmin 88"
    when "apply_price" then "/apply_price premium_6m 7.45"
    when "set_rate" then "/set_rate EUR 1.16"
    else "/#{name}"
    end
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
