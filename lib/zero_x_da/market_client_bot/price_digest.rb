# frozen_string_literal: true

require "date"
require "time"
require_relative "market_api"
require_relative "telegram_api"
require_relative "price_messages"

module ZeroXDA
  module MarketClientBot
    # Daily price application digest for admins, due at 07:00 Central
    # European Time. Cron runs at 05:00 and 06:00 UTC; due? is true for
    # exactly one of them on any given day depending on CET/CEST.
    class PriceDigest
      DIGEST_HOUR = 7
      CET_OFFSET = 3600
      CEST_OFFSET = 7200

      def initialize(market_api:, telegram_api:, clock: -> { Time.now.utc })
        @market_api = market_api
        @telegram_api = telegram_api
        @clock = clock
      end

      def due?(now = @clock.call)
        central_european_hour(now.getutc) == DIGEST_HOUR
      end

      def deliver
        delivered = 0
        admins.each do |admin|
          telegram_user_id = admin.dig("attributes", "telegram_user_id")
          begin
            proposal = @market_api.price_proposal(
              actor_telegram_user_id: telegram_user_id
            )
            # In private chats the chat id equals the telegram user id.
            @telegram_api.send_message(
              chat_id: telegram_user_id,
              text: PriceMessages.application_text(proposal),
              reply_markup: nil
            )
            delivered += 1
          rescue MarketAPI::Error, TelegramAPI::Error => error
            warn "price digest for #{telegram_user_id} failed: #{error.message}"
          end
        end
        delivered
      end

      def central_european_hour(utc_time)
        (utc_time + utc_offset_seconds(utc_time)).hour
      end

      private

      def admins
        @market_api.active_users.select do |user|
          user.dig("attributes", "role") == "admin"
        end
      end

      def utc_offset_seconds(utc_time)
        summer_time?(utc_time) ? CEST_OFFSET : CET_OFFSET
      end

      # EU DST: from the last Sunday of March, 01:00 UTC, to the last Sunday
      # of October, 01:00 UTC.
      def summer_time?(utc_time)
        utc_time >= dst_boundary(utc_time.year, 3) &&
          utc_time < dst_boundary(utc_time.year, 10)
      end

      def dst_boundary(year, month)
        last_day = Date.new(year, month, -1)
        last_sunday = last_day - last_day.wday
        Time.utc(year, month, last_sunday.day, 1)
      end
    end
  end
end
