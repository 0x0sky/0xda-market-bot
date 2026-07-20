# frozen_string_literal: true

require_relative "locale"

module ZeroXDA
  module MarketClientBot
    module I18n
      TRANSLATIONS = {
        "en_US" => {
          server_starting: "Server is starting…",
          access_denied: "Access denied.",
          command_failed: "Could not complete the command. Please try again.",
          authorization_success: "Authorization successful ✅",
          assigned_admin_notice: "You have been assigned the admin role ✅",
          choose_product_to_buy: "Choose a product to buy:",
          selected_product: "Selected: %{name}",
          product_unavailable: "Product is unavailable",
          admin_format: "Format: /setadmin @username or Telegram ID",
          price_applied: "Price applied ✅\n%{name} (%{sku})\n%{amount} USDT",
          rate_applied: "Rate applied ✅\n1 %{currency} = %{amount} USDT",
          server_status_title: "🖥️ Service status",
          active_users_title: "👥 Active users: %{count}",
          prices_title: "📦 Price application",
          rates_title: "💱 Exchange rates",
          base_currency: "Base: USDT",
          no_username: "no username",
          role_label: "Role: %{role}",
          update_single_price: "Update one: /apply_price <sku|position|name> <amount>",
          review_prices: "Review again: /apply_prices"
        },
        "uk_UA" => {
          server_starting: "Сервер запускається…",
          access_denied: "Доступ заборонено.",
          command_failed: "Не вдалося виконати команду. Спробуй ще раз.",
          authorization_success: "Авторизація успішна ✅",
          assigned_admin_notice: "Вам призначено роль admin ✅",
          choose_product_to_buy: "Обери продукт для купівлі:",
          selected_product: "Обрано: %{name}",
          product_unavailable: "Продукт недоступний",
          admin_format: "Формат: /setadmin @username або Telegram ID",
          price_applied: "Ціну застосовано ✅\n%{name} (%{sku})\n%{amount} USDT",
          rate_applied: "Курс застосовано ✅\n1 %{currency} = %{amount} USDT",
          server_status_title: "🖥️ Стан сервісів",
          active_users_title: "👥 Активні користувачі: %{count}",
          prices_title: "📦 Застосування цін",
          rates_title: "💱 Курси валют",
          base_currency: "База: USDT",
          no_username: "без username",
          role_label: "Роль: %{role}",
          update_single_price: "Змінити одну: /apply_price <sku|позиція|назва> <сума>",
          review_prices: "Переглянути знову: /apply_prices"
        }
      }.freeze

      module_function

      def translate(key, locale: Locale::DEFAULT, **variables)
        normalized = Locale.normalize(locale)
        template = TRANSLATIONS.fetch(normalized).fetch(key) do
          TRANSLATIONS.fetch(Locale::DEFAULT).fetch(key)
        end
        format(template, variables)
      end

      def format(template, variables)
        return template if variables.empty?

        template % variables
      end

      module Helpers
        private

        def t(key, locale: current_locale, **variables)
          I18n.translate(key, locale: locale, **variables)
        end

        def current_locale
          @telegram_update_locale || Locale::DEFAULT
        end
      end
    end
  end
end
