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
      MAX_REQUEST_ATTEMPTS = 6
      RETRYABLE_STATUS_CODES = %w[502 503 504].freeze
      RETRY_BACKOFF_SECONDS = [2, 4, 8, 16, 30].freeze
      TRANSIENT_ERRORS = [IOError, SystemCallError, Timeout::Error].freeze
      TELEGRAM_PROVIDER = "telegram"

      class RetryableResponseError < StandardError; end

      class Error < StandardError
        attr_reader :code

        def initialize(message, code: "market_api_error")
          @code = code
          super(message)
        end
      end

      def initialize(base_url:, token:, sleeper: Kernel.method(:sleep))
        raise ArgumentError, "Market API token must not be empty" if token.to_s.empty?

        @base_url = URI("#{base_url.delete_suffix("/")}/")
        @token = token
        @sleeper = sleeper
      end

      # Telegram is translated at the adapter boundary. Core receives only the
      # generic external-identity contract and returns an internal market user.
      def authenticate_telegram(user:, chat:)
        document = post(
          "v1/auth/external",
          provider: TELEGRAM_PROVIDER,
          provider_user_id: user.fetch("id").to_s,
          provider_data: {
            chat_id: chat.fetch("id").to_s,
            username: user["username"],
            first_name: user["first_name"],
            last_name: user["last_name"],
            language_code: user["language_code"]
          }.compact
        )
        document.fetch("data")
      end

      def health
        get("health", authenticated: false, allow_error_status: true)
      end

      # Keep Telegram presentation fields local to the bot. The core response
      # remains provider-neutral and exposes identities[] only.
      def active_users
        raw_active_users.map { |profile| adapt_user_profile(profile) }
      end

      def products(locale: "en_US")
        get(
          "v1/products?#{URI.encode_www_form(locale: locale)}",
          authenticated: true
        ).fetch("data")
      end

      def price_proposal(actor_user_id: nil, actor_telegram_user_id: nil, locale: "en_US")
        actor_user_id ||= internal_user_id_for_telegram(actor_telegram_user_id)
        get(
          "v1/admin/prices/proposal?#{URI.encode_www_form(
            actor_user_id: actor_user_id,
            locale: locale
          )}",
          authenticated: true
        ).fetch("data")
      end

      def apply_prices(actor_user_id: nil, actor_telegram_user_id: nil, prices:)
        actor_user_id ||= internal_user_id_for_telegram(actor_telegram_user_id)
        post(
          "v1/admin/prices",
          actor_user_id: actor_user_id,
          prices: prices
        ).fetch("data")
      end

      # Currency resources replaced the old fx-rate resources in core. Keep a
      # stable command-facing shape so Bot does not depend on either API model.
      def fx_rates
        get("v1/currencies", authenticated: true).fetch("data").map do |currency|
          attributes = currency.fetch("attributes")
          code = attributes.fetch("code")
          {
            "type" => "fx_rate",
            "id" => code,
            "attributes" => {
              "currency" => code,
              "usdt_per_unit" => attributes["usdt_per_unit"]
            }
          }
        end
      end

      def set_fx_rates(actor_user_id: nil, actor_telegram_user_id: nil, rates:)
        actor_user_id ||= internal_user_id_for_telegram(actor_telegram_user_id)
        prices = rates.map do |rate|
          {
            sku: rate.fetch(:currency).to_s.downcase,
            amount_usdt: rate.fetch(:usdt_per_unit)
          }
        end
        applied = apply_prices(actor_user_id: actor_user_id, prices: prices)

        rates.zip(applied).map do |rate, price|
          currency = rate.fetch(:currency).to_s.upcase
          {
            "type" => "fx_rate",
            "id" => currency,
            "attributes" => {
              "currency" => currency,
              "usdt_per_unit" => price.dig("attributes", "amount_usdt") || rate.fetch(:usdt_per_unit).to_s
            }
          }
        end
      end

      # Telegram-facing references are resolved to internal UUIDs here before
      # calling the provider-neutral core API.
      def set_admin(actor_user_id: nil, actor_telegram_user_id: nil, target:)
        actor_user_id ||= internal_user_id_for_telegram(actor_telegram_user_id)
        profile = resolve_telegram_target(target)
        assignment = post(
          "v1/admin/users/set-admin",
          actor_user_id: actor_user_id,
          target_user_id: profile.fetch("id")
        ).fetch("data")
        assignment["attributes"] = profile.fetch("attributes").merge(
          assignment.fetch("attributes")
        )
        assignment
      end

      private

      def raw_active_users
        get("v1/users?status=active", authenticated: true).fetch("data")
      end

      def adapt_user_profile(profile)
        attributes = profile.fetch("attributes")
        identities = attributes.fetch("identities", [])
        telegram = identities.find { |identity| identity["provider"] == TELEGRAM_PROVIDER }
        data = telegram&.fetch("provider_data", {}) || {}

        profile.merge(
          "attributes" => attributes.merge(
            "telegram_user_id" => telegram&.fetch("provider_user_id", nil),
            "telegram_chat_id" => data["chat_id"],
            "telegram_username" => data["username"],
            "telegram_first_name" => data["first_name"],
            "telegram_last_name" => data["last_name"],
            "language_code" => data["language_code"]
          )
        )
      end

      def internal_user_id_for_telegram(telegram_user_id)
        identifier = telegram_user_id.to_s
        raise ArgumentError, "actor Telegram user ID must not be empty" if identifier.empty?

        profile = active_users.find do |entry|
          entry.dig("attributes", "telegram_user_id").to_s == identifier
        end
        raise Error.new("Actor user is not registered", code: "not_found") unless profile

        profile.fetch("id")
      end

      def resolve_telegram_target(target)
        normalized = target.to_s.strip
        raise ArgumentError, "target must not be empty" if normalized.empty?

        profiles = active_users
        profile = if normalized.start_with?("@")
                    username = normalized.delete_prefix("@").downcase
                    profiles.find do |entry|
                      entry.dig("attributes", "telegram_username").to_s.downcase == username
                    end
                  else
                    profiles.find do |entry|
                      entry.fetch("id") == normalized ||
                        entry.dig("attributes", "telegram_user_id").to_s == normalized
                    end
                  end
        raise Error.new("Target user is not registered", code: "not_found") unless profile

        profile
      end

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
        response, document = request_with_retry(uri, request)
        return document if response.is_a?(Net::HTTPSuccess) || allow_error_status

        failure = document.fetch("errors", [{}]).first
        raise Error.new(
          failure["message"] || "Market API request failed",
          code: failure["code"] || response.code
        )
      rescue RetryableResponseError, JSON::ParserError, IOError, SystemCallError, Timeout::Error => error
        raise Error, "Market API request failed: #{error.message}"
      end

      def request_with_retry(uri, request)
        attempts = 0

        begin
          attempts += 1
          response = perform_http_request(uri, request)
          raise RetryableResponseError, "temporary HTTP #{response.code}" if retryable_status?(response)

          document = parse_document(response)
          [response, document]
        rescue *TRANSIENT_ERRORS, RetryableResponseError, JSON::ParserError
          if attempts < MAX_REQUEST_ATTEMPTS
            @sleeper.call(RETRY_BACKOFF_SECONDS.fetch(attempts - 1))
            retry
          end

          raise
        end
      end

      def retryable_status?(response)
        RETRYABLE_STATUS_CODES.include?(response.code)
      end

      def parse_document(response)
        JSON.parse(response.body)
      rescue JSON::ParserError => error
        raise JSON::ParserError, "temporary non-JSON response (HTTP #{response.code}): #{error.message}"
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
