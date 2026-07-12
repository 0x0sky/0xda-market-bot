# frozen_string_literal: true

require "set"
require "time"
require_relative "market_api"
require_relative "telegram_api"

module ZeroXDA
  module MarketClientBot
    class Bot
      MESSAGE_LIMIT = 3_800

      def initialize(market_api:, telegram_api:, admin_telegram_ids: [], clock: -> { Time.now.utc })
        @market_api = market_api
        @telegram_api = telegram_api
        @admin_telegram_ids = admin_telegram_ids.map(&:to_s).reject(&:empty?).to_set
        @clock = clock
      end

      def handle(update)
        message = update["message"]
        return unless message

        case command(message["text"])
        when "/start"
          authenticate(message)
        when "/status"
          show_status(message)
        when "/users"
          show_active_users(message)
        end
      rescue KeyError, ArgumentError, MarketAPI::Error => error
        notify_failure(message, error)
      end

      private

      def command(text)
        match = text.to_s.match(%r{\A(/\w+)(?:@\w+)?(?:\s|\z)})
        match && match[1]
      end

      def authenticate(message)
        chat = message.fetch("chat")
        user = @market_api.authenticate_telegram(
          user: message.fetch("from"),
          chat: chat
        )
        send_message(chat.fetch("id"), success_message(user))
      end

      def show_status(message)
        health = @market_api.health
        core_status = health.fetch("status", "unknown")
        core_time = health.fetch("server_time", "—")
        bot_time = timestamp(@clock.call)
        text = <<~TEXT.strip
          zeroxda-market / status

          market core: #{status_label(core_status)}
          core time: #{core_time}

          client bot: ok ✅
          bot time: #{bot_time}
        TEXT
        send_message(message.fetch("chat").fetch("id"), text)
      end

      def show_active_users(message)
        telegram_user_id = message.fetch("from").fetch("id").to_s
        unless @admin_telegram_ids.include?(telegram_user_id)
          return send_message(message.fetch("chat").fetch("id"), "доступ заборонено.")
        end

        users = @market_api.active_users
        user_messages(users).each do |text|
          send_message(message.fetch("chat").fetch("id"), text)
        end
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
