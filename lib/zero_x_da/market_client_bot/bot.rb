# frozen_string_literal: true

require "time"
require_relative "market_api"
require_relative "telegram_api"

module ZeroXDA
  module MarketClientBot
    class Bot
      MESSAGE_LIMIT = 3_800
      PUBLIC_COMMANDS = [
        { command: "start", description: "авторизація" },
        { command: "status", description: "власний статус" }
      ].freeze
      ADMIN_COMMANDS = [
        *PUBLIC_COMMANDS,
        { command: "servers", description: "стан серверів" },
        { command: "users", description: "активні користувачі" },
        { command: "setadmin", description: "призначити адміністратора" }
      ].freeze

      def initialize(market_api:, telegram_api:, clock: -> { Time.now.utc })
        @market_api = market_api
        @telegram_api = telegram_api
        @clock = clock
      end

      def handle(update)
        message = update["message"]
        return unless message

        command, argument = parse_command(message["text"])
        case command
        when "/start"
          authenticate(message)
        when "/status"
          show_status(message)
        when "/servers"
          show_servers(message)
        when "/users"
          show_active_users(message)
        when "/setadmin"
          set_admin(message, argument)
        end
      rescue KeyError, ArgumentError, MarketAPI::Error => error
        notify_failure(message, error)
      end

      private

      def parse_command(text)
        match = text.to_s.match(%r{\A(/\w+)(?:@\w+)?(?:\s+(.+)|\z)})
        [match&.[](1)&.downcase, match&.[](2)&.strip]
      end

      def authenticate(message)
        chat = message.fetch("chat")
        user = @market_api.authenticate_telegram(
          user: message.fetch("from"),
          chat: chat
        )
        chat_id = chat.fetch("id")
        send_message(chat_id, success_message(user))
        sync_commands(chat_id, user)
      end

      def show_status(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        send_message(chat_id, user_status_message(user))
      end

      def show_servers(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, "доступ заборонено.") unless admin?(user)

        health = @market_api.health
        core_status = health.fetch("status", "unknown")
        core_time = health.fetch("server_time", "—")
        bot_time = timestamp(@clock.call)
        text = <<~TEXT.strip
          zeroxda-market / servers

          market core: #{status_label(core_status)}
          core time: #{core_time}

          client bot: ok ✅
          bot time: #{bot_time}
        TEXT
        send_message(chat_id, text)
      end

      def show_active_users(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, "доступ заборонено.") unless admin?(user)

        users = @market_api.active_users
        user_messages(users).each do |text|
          send_message(chat_id, text)
        end
      end

      def set_admin(message, target)
        chat_id = message.fetch("chat").fetch("id")
        actor = authenticate_user(message)
        sync_commands(chat_id, actor)
        return send_message(chat_id, "доступ заборонено.") unless admin?(actor)
        if target.to_s.empty?
          return send_message(chat_id, "формат: /setadmin @username або Telegram ID")
        end

        assignment = @market_api.set_admin(
          actor_telegram_user_id: message.fetch("from").fetch("id"),
          target: target
        )
        attributes = assignment.fetch("attributes")
        target_chat_id = attributes["telegram_chat_id"]
        sync_admin_target(target_chat_id, chat_id)
        text = <<~TEXT.strip
          admin призначений ✅

          telegram: #{attributes.fetch("telegram_user_id")}
          uuid: #{assignment.fetch("id")}
          role: #{attributes.fetch("role")}
        TEXT
        send_message(chat_id, text)
      end

      def authenticate_user(message)
        @market_api.authenticate_telegram(
          user: message.fetch("from"),
          chat: message.fetch("chat")
        )
      end

      def sync_commands(chat_id, user)
        commands = admin?(user) ? ADMIN_COMMANDS : PUBLIC_COMMANDS
        @telegram_api.set_commands(
          commands,
          scope: { type: "chat", chat_id: chat_id }
        )
      rescue TelegramAPI::Error => error
        warn "command menu sync failed: #{error.message}"
      end

      def sync_admin_target(target_chat_id, actor_chat_id)
        return if target_chat_id.to_s.empty?

        @telegram_api.set_commands(
          ADMIN_COMMANDS,
          scope: { type: "chat", chat_id: target_chat_id }
        )
        return if target_chat_id.to_s == actor_chat_id.to_s

        send_message(target_chat_id, "вам призначено роль admin ✅")
      rescue TelegramAPI::Error => error
        warn "new admin menu sync failed: #{error.message}"
      end

      def admin?(user)
        user.dig("attributes", "role") == "admin"
      end

      def user_messages(users)
        messages = ["zeroxda-market / active users: #{users.length}"]
        users.each do |user|
          attributes = user.fetch("attributes")
          block = <<~TEXT.strip
            telegram: #{attributes.fetch("telegram_user_id")}
            uuid: #{user.fetch("id")}
            role: #{attributes.fetch("role")}
          TEXT
          candidate = "#{messages.last}\n\n#{block}"
          if candidate.bytesize > MESSAGE_LIMIT
            messages << block
          else
            messages[-1] = candidate
          end
        end
        messages
      end

      def success_message(user)
        id = user.fetch("id")
        role = user.dig("attributes", "role")
        <<~TEXT.strip
          zeroxda-market

          авторизація успішна ✅
          role: #{role}
          user: #{id[0, 8]}
        TEXT
      end

      def user_status_message(user)
        id = user.fetch("id")
        role = user.dig("attributes", "role")
        status = user.dig("attributes", "status")
        indicator = status == "active" ? "✅" : "❌"
        <<~TEXT.strip
          zeroxda-market / status

          role: #{role}
          user: #{id[0, 8]}
          status: #{status} #{indicator}
        TEXT
      end

      def status_label(status)
        status == "ok" ? "ok ✅" : "#{status} ❌"
      end

      def timestamp(value)
        raise ArgumentError, "clock must return a Time" unless value.is_a?(Time)

        value.utc.iso8601(6)
      end

      def send_message(chat_id, text)
        @telegram_api.send_message(chat_id: chat_id, text: text)
      end

      def notify_failure(message, error)
        chat_id = message&.dig("chat", "id")
        return unless chat_id

        send_message(chat_id, "не вдалося виконати команду. спробуй ще раз.")
        warn "command failed: #{error.class}: #{error.message}"
      rescue TelegramAPI::Error
        nil
      end
    end
  end
end
