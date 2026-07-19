# frozen_string_literal: true

require "json"
require "rack"
require "time"

module ZeroXDA
  module MarketClientBot
    class AsyncDispatcher
      def call(&task)
        Thread.new do
          task.call
        rescue StandardError => error
          warn "background update failed: #{error.class}: #{error.message}"
        end.tap { |thread| thread.report_on_exception = false }
      end
    end

    class WebApp
      JSON_HEADERS = {
        "content-type" => "application/json; charset=utf-8",
        "cache-control" => "no-store"
      }.freeze

      def initialize(
        bot:,
        webhook_secret:,
        dispatcher: AsyncDispatcher.new,
        revision: ENV.fetch("RENDER_GIT_COMMIT", "unknown")
      )
        raise ArgumentError, "Webhook secret must not be empty" if webhook_secret.to_s.empty?

        @bot = bot
        @webhook_secret = webhook_secret
        @dispatcher = dispatcher
        @revision = revision.to_s.empty? ? "unknown" : revision.to_s
      end

      def call(environment)
        request = Rack::Request.new(environment)
        if request.get? && request.path_info == "/health"
          return json_response(
            200,
            status: "ok",
            server_time: Time.now.utc.iso8601(6),
            revision: @revision
          )
        end

        if request.post? && request.path_info == "/telegram/webhook"
          return json_response(401, error: "unauthorized") unless authorized?(request)

          update = JSON.parse(request.body.read(1_048_577))
          @dispatcher.call { @bot.handle(update) }
          return json_response(200, status: "accepted")
        end

        json_response(404, error: "not_found")
      rescue JSON::ParserError
        json_response(400, error: "invalid_json")
      end

      private

      def authorized?(request)
        provided = request.get_header("HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN").to_s
        secure_compare(provided, @webhook_secret)
      end

      def secure_compare(left, right)
        return false if left.empty? || left.bytesize != right.bytesize

        left.bytes.zip(right.bytes).reduce(0) { |result, (a, b)| result | (a ^ b) }.zero?
      end

      def json_response(status, document)
        [status, JSON_HEADERS, [JSON.generate(document)]]
      end
    end
  end
end
