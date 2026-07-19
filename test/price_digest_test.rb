# frozen_string_literal: true

require_relative "test_helper"
require "zero_x_da/market_client_bot/price_digest"

class PriceDigestTest < Minitest::Test
  def test_delivers_the_database_driven_form_in_the_admin_locale
    market = Class.new(FakeMarketAPI) do
      def active_users
        super.map do |user|
          user.tap { |entry| entry.fetch("attributes")["role"] = "admin" }
        end
      end
    end.new
    telegram = FakeTelegramAPI.new
    digest = ZeroXDA::MarketClientBot::PriceDigest.new(
      market_api: market,
      telegram_api: telegram
    )

    assert_equal 1, digest.deliver
    assert_equal "uk_UA", market.price_proposal_requests.first.fetch(:locale)
    assert_includes telegram.messages.first.fetch(:text), "застосування цін"
    assert_includes telegram.messages.first.fetch(:text), "Telegram Premium 3 міс."
  end
end
