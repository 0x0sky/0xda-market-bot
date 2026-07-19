# frozen_string_literal: true

module ZeroXDA
  module MarketClientBot
    # Bot-owned interface copy. Product names and ordering are deliberately
    # absent: those arrive from the localized database catalog via the API.
    module PriceMessages
      COPY = {
        "en_US" => {
          title: "0xda-market / price application",
          base_currency: "base currency: USDT",
          previous: "yesterday",
          current: "current",
          edited_by: "edited by",
          applied_at: "applied at",
          update: "Update a price: /apply_price <sku|position|short name> <amount in USDT>",
          review: "Review all prices again: /apply_prices",
          persistence: "Until a new application is submitted, the last applied prices remain in effect.",
          usage: "format: /apply_price <sku|position|short name> <amount in USDT>\n" \
                 "example: /apply_price Premium 6m 7.45"
        },
        "uk_UA" => {
          title: "0xda-market / застосування цін",
          base_currency: "базова валюта: USDT",
          previous: "вчора",
          current: "поточна",
          edited_by: "редактор",
          applied_at: "застосовано",
          update: "Оновити ціну: /apply_price <sku|позиція|коротка назва> <сума в USDT>",
          review: "Переглянути всі ціни: /apply_prices",
          persistence: "До наступного застосування діють останні встановлені ціни.",
          usage: "формат: /apply_price <sku|позиція|коротка назва> <сума в USDT>\n" \
                 "приклад: /apply_price Premium 6m 7.45"
        }
      }.freeze

      module_function

      def application_text(proposal, locale: "en_US")
        copy = copy_for(locale)
        lines = [copy.fetch(:title), copy.fetch(:base_currency), ""]
        proposal.each do |entry|
          attributes = entry.fetch("attributes")
          lines << "#{attributes.fetch("position")}. #{attributes.fetch("name")} (#{entry.fetch("id")})"
          lines << "   #{copy.fetch(:previous)}: #{amount_label(attributes["previous_amount_usdt"])} · " \
                   "#{copy.fetch(:current)}: #{amount_label(attributes["current_amount_usdt"])}"
          lines << "   #{copy.fetch(:edited_by)}: #{value_label(attributes["current_edited_by_user_id"])} · " \
                   "#{copy.fetch(:applied_at)}: #{value_label(attributes["current_applied_at"])}"
        end
        lines << ""
        lines << copy.fetch(:update)
        lines << copy.fetch(:review)
        lines << copy.fetch(:persistence)
        lines.join("\n")
      end

      def apply_price_usage(locale: "en_US")
        copy_for(locale).fetch(:usage)
      end

      def amount_label(value)
        value.nil? || value.to_s.empty? ? "—" : value.to_s
      end

      def value_label(value)
        value.nil? || value.to_s.empty? ? "—" : value.to_s
      end

      def copy_for(locale)
        COPY.fetch(locale.to_s, COPY.fetch("en_US"))
      end
    end
  end
end
