require_relative "test_helper"
require "zero_x_da/market_client_bot/price_messages"

class PriceMessagesTest < Minitest::Test
  PriceMessages = ZeroXDA::MarketClientBot::PriceMessages

  def test_renders_both_amounts_when_both_are_present
    text = PriceMessages.application_text([entry], locale: "uk_UA")

    assert_includes text, "вчора: 7.20 · поточна: 7.45"
    assert_includes text, "редактор: uuid-1 · застосовано: 2026-07-19T07:00:00.000000Z"
  end

  def test_skips_the_previous_label_when_there_is_no_previous_amount
    text = PriceMessages.application_text(
      [entry("previous_amount_usdt" => nil)],
      locale: "uk_UA"
    )

    refute_includes text, "вчора"
    refute_includes text, "—"
    assert_includes text, "поточна: 7.45"
  end

  def test_omits_amount_and_detail_lines_entirely_when_no_price_exists
    text = PriceMessages.application_text(
      [entry(
        "previous_amount_usdt" => nil,
        "current_amount_usdt" => nil,
        "current_edited_by_user_id" => nil,
        "current_applied_at" => ""
      )],
      locale: "uk_UA"
    )

    assert_includes text, "1. Telegram Premium 3 міс. (premium_3m)"
    refute_includes text, "вчора"
    refute_includes text, "поточна"
    refute_includes text, "редактор"
    refute_includes text, "застосовано"
    refute_includes text, "—"
  end

  private

  def entry(overrides = {})
    {
      "type" => "price",
      "id" => "premium_3m",
      "attributes" => {
        "name" => "Telegram Premium 3 міс.",
        "position" => 1,
        "previous_amount_usdt" => "7.20",
        "current_amount_usdt" => "7.45",
        "current_edited_by_user_id" => "uuid-1",
        "current_applied_at" => "2026-07-19T07:00:00.000000Z"
      }.merge(overrides)
    }
  end
end
