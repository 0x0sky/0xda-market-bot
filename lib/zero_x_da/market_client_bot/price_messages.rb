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
                 "example: /apply_price Premium 6m 7.45",
          choose_product: "choose a product to update:",
          enter_amount: "enter the new price for %s in USDT, e.g. 7.45",
          invalid_amount: "invalid amount. enter a number, e.g. 7.45",
          product_not_found: "product not found: %s\n" \
                             "enter a sku, position or short name, or pick a product button"
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
                 "приклад: /apply_price Premium 6m 7.45",
          choose_product: "обери продукт для оновлення ціни:",
          enter_amount: "введи нову ціну для %s у USDT, наприклад 7.45",
          invalid_amount: "некоректна сума. введи число, наприклад 7.45",
          product_not_found: "продукт не знайдено: %s\n" \
                             "введи sku, позицію або коротку назву, або обери продукт кнопкою"
        }
      }.freeze

      module_function

      def application_text(proposal, locale: "en_US")
        copy = copy_for(locale)
        lines = [copy.fetch(:title), copy.fetch(:base_currency), ""]
        proposal.each do |entry|
          attributes = entry.fetch("attributes")
          lines << "#{attributes.fetch("position")}. #{attributes.fetch("name")} (#{entry.fetch("id")})"

          amounts = labeled_parts(copy,
                                  previous: attributes["previous_amount_usdt"],
                                  current: attributes["current_amount_usdt"])
          lines << "   #{amounts}" unless amounts.empty?

          details = labeled_parts(copy,
                                  edited_by: attributes["current_edited_by_user_id"],
                                  applied_at: attributes["current_applied_at"])
          lines << "   #{details}" unless details.empty?
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

      def choose_product(locale: "en_US")
        copy_for(locale).fetch(:choose_product)
      end

      def enter_amount(name, locale: "en_US")
        format(copy_for(locale).fetch(:enter_amount), name)
      end

      def invalid_amount(locale: "en_US")
        copy_for(locale).fetch(:invalid_amount)
      end

      def product_not_found(reference, locale: "en_US")
        format(copy_for(locale).fetch(:product_not_found), reference)
      end

      # Renders only labels whose values are present; skips empty ones entirely.
      def labeled_parts(copy, pairs)
        pairs.filter_map do |label_key, value|
          next if value.nil? || value.to_s.empty?

          "#{copy.fetch(label_key)}: #{value}"
        end.join(" · ")
      end

      def copy_for(locale)
        COPY.fetch(locale.to_s, COPY.fetch("en_US"))
      end
    end
  end
end
