# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

module ZeroXDA
  module MarketClientBot
    class MarketAPI
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 75
      MAX_REQUEST_ATTEMPTS = 2
      TRANSIENT_ERRORS = [IOError, SystemCallError, Timeout::Error].freeze

      class Error < StandardError
        attr_reader :code

        def initialize(message, code: "market_api_error")
          @code = code
          super(message)
        end
      end

      def initialize(base_url:, token:)
        raise ArgumentError, "Market API token must not be empty" if token.to_s.empty?

        @base_url = URI("#{base_url.delete_suffix("/")}/")
        @token = token
      end

      def authenticate_telegram(user:, chat:)
        document = post(
          "v1/auth/telegram",
          telegram_user_id: user.fetch("id"),
          chat_id: chat.fetch("id"),
          username: user["username"],
          first_name: user["first_name"],
          last_name: user["last_name"],
          language_code: user["language_code"]
        )
        document.fetch("data")
      end

      def health
        get("health", authenticated: false, allow_error_status: true)
      end

      def active_users
        get("v1/users?status=active", authenticated: true).fetch("data")
      end

      def set_admin(actor_telegram_user_id:, target:)
        post(
          "v1/admin/users/set-admin",
          actor_telegram_user_id: actor_telegram_user_id,
          target: target
        ).fetch("data")
      end

      private

      def get(path, authenticated:, allow_error_status: false)
        uri = URI.join(@base_url, path)
        request = Net::HTTP::Get.new(uri)
        request["authorization"] = "Bearer #{@token}" if authenticated
        perform(uri, request, allow_error_status: allow_error_status)
      end

      def post(path, payload)
        uri = URI.join(@base_url, path)
        request = Net::HTTP::Post.new(uri)
        request["authorization"] = "Bearer #{@token}"
        request["content-type"] = "application/json"
        request.body = JSON.generate(payload)
        perform(uri, request)
      end

      def perform(uri, request, allow_error_status: false)
        response = request_with_retry(uri, request)
        document = JSON.parse(response.body)
        return document if response.is_a?(Net::HTTPSuccess) || allow_error_status

        failure = document.fetch("errors", [{}]).first
        raise Error.new(
          failure["message"] || "Market API request failed",
          code: failure["code"] || response.code
        )
      rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error => error
        raise Error, "Market API request failed: #{error.message}"
      end

      def request_with_retry(uri, request)
        attempts = 0

        begin
          attempts += 1
          perform_http_request(uri, request)
        rescue *TRANSIENT_ERRORS
          retry if attempts < MAX_REQUEST_ATTEMPTS

          raise
        end
      end

      def perform_http_request(uri, request)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https"
        ) do |http|
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          http.request(request)
        end
      end
    end
  end
end
