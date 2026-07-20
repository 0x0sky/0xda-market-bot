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
          servers: "📊 server status",
          users: "👥 active users",
          setadmin: "🔑 assign administrator",
          apply_prices: "📦 apply prices",
          apply_price: "💰 set product price",
          rates: "💱 exchange rates (USDT base)",
          set_rate: "⚙️ set exchange rate"
        },
        "uk_UA" => {
          start: "🔐 авторизація",
          buy: "🛍️ купити",
          status: "👤 власний статус",
          servers: "📊 стан серверів",
          users: "👥 активні користувачі",
          setadmin: "🔑 призначити адміністратора",
          apply_prices: "📦 застосувати ціни",
          apply_price: "💰 встановити ціну продукту",
          rates: "💱 курси валют відносно USDT",
          set_rate: "⚙️ встановити курс валюти"
        }
      }.freeze

      CLIENT_COMMANDS = %i[buy status].freeze
      ADMIN_WORK_COMMANDS = %i[apply_prices apply_price rates set_rate].freeze
      ADMIN_FOOTER_COMMANDS = %i[status servers users setadmin].freeze
      ADMIN_COMMANDS = (ADMIN_WORK_COMMANDS + ADMIN_FOOTER_COMMANDS.drop(1)).freeze
      TRANSIENT_COMMANDS = %w[/status /servers].freeze

      module_function

      def start(locale: Locale::DEFAULT)
        commands_for([:start], locale: locale)
      end

      def client(locale: Locale::DEFAULT)
        commands_for(CLIENT_COMMANDS, locale: locale)
      end

      def admin(locale: Locale::DEFAULT)
        commands_for([:buy] + ADMIN_WORK_COMMANDS + ADMIN_FOOTER_COMMANDS, locale: locale)
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
      CONTEXT_KEY = "zero_xda_market_client_bot_transient_command"

      def handle(update)
        message = update["message"]
        command = transient_command(message)
        previous_context = Thread.current[CONTEXT_KEY]
        context = command && { messages: [] }
        Thread.current[CONTEXT_KEY] = context if context

        super
      ensure
        if context
          schedule_incoming_command_deletion(message)
          schedule_response_deletions(context)
          Thread.current[CONTEXT_KEY] = previous_context
        end
      end

      def send_message(chat_id, text, reply_markup: nil)
        message = super
        context = Thread.current[CONTEXT_KEY]
        context&.fetch(:messages)&.push([chat_id, message])
        message
      end

      private :send_message

      private

      def transient_command(message)
        return unless message

        command = message["text"].to_s.match(%r{\A(/\w+)(?:@\w+)?(?:\s|\z)})&.[](1)&.downcase
        command if CommandMenu::TRANSIENT_COMMANDS.include?(command)
      end

      def schedule_incoming_command_deletion(message)
        chat_id = message&.dig("chat", "id")
        message_id = message&.fetch("message_id", nil)
        return unless chat_id && message_id

        schedule_message_deletion(chat_id, { "message_id" => message_id })
      end

      def schedule_response_deletions(context)
        context.fetch(:messages).each do |chat_id, message|
          schedule_message_deletion(chat_id, message)
        end
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
