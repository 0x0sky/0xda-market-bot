# frozen_string_literal: true

require_relative "locale"

module ZeroXDA
  module MarketClientBot
    module CommandMenu
      COPY = {
        "en_US" => {
          start: "🔐 authorization",
          buy: "🛍️ buy",
          status: "👤 account status",
          apply_prices: "🛠️ 📦 apply prices",
          apply_price: "🛠️ 💰 set product price (USDT)",
          rates: "🛠️ 💱 exchange rates (USDT base)",
          set_rate: "🛠️ ⚙️ set exchange rate",
          users: "🛠️ 👥 active users",
          servers: "🛠️ 📊 server status",
          setadmin: "🛠️ 🔑 assign administrator"
        },
        "uk_UA" => {
          start: "🔐 авторизація",
          buy: "🛍️ купити",
          status: "👤 власний статус",
          apply_prices: "🛠️ 📦 застосувати ціни",
          apply_price: "🛠️ 💰 встановити ціну продукту",
          rates: "🛠️ 💱 курси валют відносно USDT",
          set_rate: "🛠️ ⚙️ встановити курс валюти",
          users: "🛠️ 👥 активні користувачі",
          servers: "🛠️ 📊 стан серверів",
          setadmin: "🛠️ 🔑 призначити адміністратора"
        }
      }.freeze

      CLIENT_COMMANDS = %i[buy status].freeze
      ADMIN_COMMANDS = %i[servers users setadmin apply_prices apply_price rates set_rate].freeze
      TRANSIENT_COMMANDS = ([:status] + ADMIN_COMMANDS).map { |name| "/#{name}" }.freeze

      module_function

      def start(locale: Locale::DEFAULT)
        commands_for([:start], locale: locale)
      end

      def client(locale: Locale::DEFAULT)
        commands_for(CLIENT_COMMANDS, locale: locale)
      end

      def admin(locale: Locale::DEFAULT)
        commands_for(CLIENT_COMMANDS + ADMIN_COMMANDS, locale: locale)
      end

      def commands_for(names, locale:)
        copy = COPY.fetch(Locale.normalize(locale), COPY.fetch(Locale::DEFAULT))
        names.map { |name| { command: name.to_s, description: copy.fetch(name) } }
      end
    end

    module CommandMenuLocalization
      private

      def sync_commands(chat_id, user)
        locale = user.dig("attributes", "locale") || @telegram_update_locale || Locale::DEFAULT
        commands = admin?(user) ? CommandMenu.admin(locale: locale) : CommandMenu.client(locale: locale)
        @telegram_api.set_commands(commands, scope: { type: "chat", chat_id: chat_id })
      rescue TelegramAPI::Error => error
        warn "command menu sync failed: #{error.message}"
      end

      def sync_admin_target(target_chat_id, actor_chat_id)
        return if target_chat_id.to_s.empty?

        @telegram_api.set_commands(
          CommandMenu.admin(locale: Locale::DEFAULT),
          scope: { type: "chat", chat_id: target_chat_id }
        )
        return if target_chat_id.to_s == actor_chat_id.to_s

        send_message(target_chat_id, "вам призначено роль admin ✅")
      rescue TelegramAPI::Error => error
        warn "new admin menu sync failed: #{error.message}"
      end
    end

    module TransientUserCommands
      def handle(update)
        super
      ensure
        delete_transient_user_command(update["message"])
      end

      private

      def delete_transient_user_command(message)
        return unless message

        command = message["text"].to_s.match(%r{\A(/\w+)(?:@\w+)?(?:\s|\z)})&.[](1)&.downcase
        return unless CommandMenu::TRANSIENT_COMMANDS.include?(command)

        chat_id = message.dig("chat", "id")
        message_id = message["message_id"]
        return unless chat_id && message_id

        @telegram_api.delete_message(chat_id: chat_id, message_id: message_id)
      rescue TelegramAPI::Error => error
        warn "user command deletion failed: #{error.message}"
      end
    end

    module TelegramUpdateLocale
      def handle(update)
        language_code = update.dig("message", "from", "language_code") ||
                        update.dig("callback_query", "from", "language_code")
        @telegram_update_locale = Locale.resolve(language_code)
        super
      ensure
        @telegram_update_locale = nil
      end
    end

    Bot.prepend(CommandMenuLocalization)
    Bot.prepend(TransientUserCommands)
    Bot.prepend(TelegramUpdateLocale)
  end
end
