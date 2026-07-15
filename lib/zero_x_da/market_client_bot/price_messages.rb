# frozen_string_literal: true

module ZeroXDA
  module MarketClientBot
    # English-only for now: the single supported localization language.
    # Shared by the /apply_prices command and the daily digest.
    module PriceMessages
      APPLY_PRICE_USAGE =
        "format: /apply_price <sku|position> <amount in USDT>\n" \
        "example: /apply_price premium_6m 7.45"

      module_function

      def application_text(proposal)
        lines = ["0xda-market / price application", "base currency: USDT", ""]
        proposal.each do |entry|
          attributes = entry.fetch("attributes")
          lines << "#{attributes.fetch("position")}. #{attributes.fetch("name")} (#{entry.fetch("id")})"
          lines << "   yesterday: #{amount_label(attributes["previous_amount_usdt"])} · " \
                   "current: #{amount_label(attributes["current_amount_usdt"])}"
        end
        lines << ""
        lines << "Update a price: /apply_price <sku|position> <amount in USDT>"
        lines << "Review all prices again: /apply_prices"
        lines << "Until a new application is submitted, the last applied prices remain in effect."
        lines.join("\n")
      end

      def amount_label(value)
        value.nil? || value.to_s.empty? ? "—" : value.to_s
      end
    end
  end
end
