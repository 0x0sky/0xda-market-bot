# frozen_string_literal: true

require_relative "market_api"
require_relative "telegram_api"

module ZeroXDA
  module MarketClientBot
    class Bot
      def initialize(market_api:, telegram_api:)
        @market_api = market_api
        @telegram_api = telegram_api
      end

      def handle(update)
        message = update["message"]
        return unless message
        return unless start_command?(message["text"])

        chat = message.fetch("chat")
        user = @market_api.authenticate_telegram(
          user: message.fetch("from"),
          chat: chat
        )
        @telegram_api.send_message(
          chat_id: chat.fetch("id"),
          text: success_message(user)
        )
      rescue KeyError, ArgumentError, MarketAPI::Error => error
        notify_failure(message, error)
      end

      private

      def start_command?(text)
        text.to_s.match?(%r{\A/start(?:@\w+)?(?:\s|\z)})
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

      def notify_failure(message, error)
        chat_id = message&.dig("chat", "id")
        return unless chat_id

        @telegram_api.send_message(
          chat_id: chat_id,
          text: "не вдалося авторизуватися. спробуй /start ще раз."
        )
        warn "authentication failed: #{error.class}: #{error.message}"
      rescue TelegramAPI::Error
        nil
      end
    end
  end
end
