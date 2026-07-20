# frozen_string_literal: true

require_relative "timestamp_formatter"
require_relative "i18n"

module ZeroXDA
  module MarketClientBot
    module AdminMessages
      include I18n::Helpers

      private

      def show_servers(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, t(:access_denied)) unless admin?(user)

        health = @market_api.health
        text = <<~TEXT.strip
          #{t(:server_status_title)}

          #{status_icon(health.fetch("status", "unknown"))} Market core
          🕒 #{TimestampFormatter.format(health["server_time"])}

          ✅ Client bot
          🕒 #{TimestampFormatter.format(@clock.call)}
        TEXT
        send_message(chat_id, text)
      end

      def show_active_users(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, t(:access_denied)) unless admin?(user)

        user_messages(@market_api.active_users).each { |text| send_message(chat_id, text) }
      end

      def start_price_application(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, t(:access_denied)) unless admin?(user)

        locale = locale_for(message)
        proposal = @market_api.price_proposal(
          actor_telegram_user_id: message.fetch("from").fetch("id"),
          locale: locale
        )
        usernames = editor_usernames(@market_api.active_users)
        send_message(chat_id, price_application_text(proposal, usernames: usernames, locale: locale))
      end

      def show_fx_rates(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, t(:access_denied)) unless admin?(user)

        lines = [t(:rates_title), t(:base_currency), ""]
        @market_api.fx_rates.each do |rate|
          attributes = rate.fetch("attributes")
          lines << "• 1 #{attributes.fetch("currency")} = #{attributes.fetch("usdt_per_unit")} USDT"
          updated_at = attributes["updated_at"]
          lines << "  🕒 #{TimestampFormatter.format(updated_at)}" if updated_at
        end
        lines << ""
        lines << "/set_rate <currency> <USDT per unit>"
        send_message(chat_id, lines.join("\n"))
      end

      def set_admin(message, target)
        chat_id = message.fetch("chat").fetch("id")
        actor = authenticate_user(message)
        sync_commands(chat_id, actor)
        return send_message(chat_id, t(:access_denied)) unless admin?(actor)
        return send_message(chat_id, t(:admin_format)) if target.to_s.empty?

        assignment = @market_api.set_admin(
          actor_telegram_user_id: message.fetch("from").fetch("id"),
          target: target
        )
        attributes = assignment.fetch("attributes")
        sync_admin_target(attributes["telegram_chat_id"], chat_id)
        send_message(
          chat_id,
          "🔑 #{t(:assigned_admin_notice)}\n\n" \
          "👤 #{display_username(attributes)}\n" \
          "#{t(:role_label, role: attributes.fetch("role"))}"
        )
      end

      def user_messages(users)
        messages = [t(:active_users_title, count: users.length)]
        users.each do |user|
          attributes = user.fetch("attributes")
          block = <<~TEXT.strip
            👤 #{display_username(attributes)}
            #{t(:role_label, role: attributes.fetch("role"))}
          TEXT
          candidate = "#{messages.last}\n\n#{block}"
          candidate.bytesize > Bot::MESSAGE_LIMIT ? messages << block : messages[-1] = candidate
        end
        messages
      end

      def price_application_text(proposal, usernames:, locale:)
        lines = [t(:prices_title, locale: locale), "💵 USDT", ""]

        proposal.each do |entry|
          attributes = entry.fetch("attributes")
          lines << "#{attributes.fetch("position")}. #{attributes.fetch("name")} · #{entry.fetch("id")}"

          previous = attributes["previous_amount_usdt"]
          current = attributes["current_amount_usdt"]
          lines << "   ⏮ #{previous} → 💰 #{current} USDT" if previous || current

          editor_id = attributes["current_edited_by_user_id"]
          editor = usernames[editor_id.to_s] || username_from(attributes)
          lines << "   ✏️ #{editor}" if editor

          applied_at = attributes["current_applied_at"]
          lines << "   🕒 #{TimestampFormatter.format(applied_at)}" if applied_at
          lines << ""
        end

        lines << t(:update_single_price, locale: locale)
        lines << t(:review_prices, locale: locale)
        lines.join("\n").strip
      end

      def editor_usernames(users)
        users.each_with_object({}) do |user, result|
          username = display_username(user.fetch("attributes"), fallback: nil)
          result[user.fetch("id").to_s] = username if username
        end
      end

      def username_from(attributes)
        value = attributes["current_edited_by_username"] || attributes["current_edited_by_telegram_username"]
        normalize_username(value)
      end

      def display_username(attributes, fallback: nil)
        normalize_username(attributes["telegram_username"] || attributes["username"]) || fallback || t(:no_username)
      end

      def normalize_username(value)
        value = value.to_s.strip
        return nil if value.empty?

        value.start_with?("@") ? value : "@#{value}"
      end

      def status_icon(status)
        status == "ok" ? "✅" : "❌"
      end
    end

    Bot.prepend(AdminMessages)
  end
end
