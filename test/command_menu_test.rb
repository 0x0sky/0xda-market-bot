# frozen_string_literal: true

require_relative "test_helper"
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
end
