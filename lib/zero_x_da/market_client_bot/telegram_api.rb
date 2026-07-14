# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

module ZeroXDA
  module MarketClientBot
    class TelegramAPI
      class Error < StandardError; end

      def initialize(token:)
        raise ArgumentError, "Telegram token must not be empty" if token.to_s.empty?

        @base_url = URI("https://api.telegram.org/bot#{token}/")
      end

      def send_message(chat_id:, text:)
        post("sendMessage", chat_id: chat_id, text: text)
      end

      def delete_message(chat_id:, message_id:)
        post("deleteMessage", chat_id: chat_id, message_id: message_id)
      end

      def set_webhook(url:, secret_token:)
        post(
          "setWebhook",
          url: url,
          secret_token: secret_token,
          allowed_updates: ["message"],
          drop_pending_updates: false
        )
      end

      def set_commands(commands, scope: nil)
        payload = { commands: commands }
        payload[:scope] = scope if scope
        post("setMyCommands", payload)
      end

      private

      def post(method, payload)
        uri = URI.join(@base_url, method)
        request = Net::HTTP::Post.new(uri)
        request["content-type"] = "application/json"
        request.body = JSON.generate(payload)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.open_timeout = 5
          http.read_timeout = 10
          http.request(request)
        end
        document = JSON.parse(response.body)
        unless response.is_a?(Net::HTTPSuccess) && document["ok"]
          raise Error, document["description"] || "Telegram API request failed"
        end

        document["result"]
      rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error => error
        raise Error, "Telegram API request failed: #{error.message}"
      end
    end
  end
end
