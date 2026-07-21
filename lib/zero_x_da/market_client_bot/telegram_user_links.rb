# frozen_string_literal: true

require "cgi"
require_relative "locale"

module ZeroXDA
  module MarketClientBot
    module TelegramUserLinks
      private

      def parse_command(text)
        command, argument = super
        command = "/setadmin" if command == "/set_admin"
        [command, argument]
      end

      def show_active_users(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, t(:access_denied)) unless admin?(user)

        user_messages_with_links(@market_api.active_users).each do |text|
          send_html_message(chat_id, text)
        end
      end

      def set_admin(message, target)
        chat_id = message.fetch("chat").fetch("id")
        actor = authenticate_user(message)
        sync_commands(chat_id, actor)
        return send_message(chat_id, t(:access_denied)) unless admin?(actor)
        return send_message(chat_id, "формат: /set_admin @username або Telegram ID") if target.to_s.empty?

        assignment = @market_api.set_admin(
          actor_telegram_user_id: message.fetch("from").fetch("id"),
          target: target
        )
        attributes = assignment.fetch("attributes")
        sync_admin_target(attributes["telegram_chat_id"], chat_id)
        send_html_message(
          chat_id,
          "🔑 #{html(t(:assigned_admin_notice))}\n\n" \
          "👤 #{telegram_user_link(attributes)}\n" \
          "#{html(t(:role_label, role: attributes.fetch("role")))}"
        )
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
        users = @market_api.active_users.each_with_object({}) do |entry, result|
          result[entry.fetch("id").to_s] = telegram_user_link(entry.fetch("attributes"))
        end
        send_html_message(chat_id, price_application_text_with_links(proposal, users: users, locale: locale))
      end

      def user_messages_with_links(users)
        messages = [html(t(:active_users_title, count: users.length))]
        users.each do |user|
          attributes = user.fetch("attributes")
          block = <<~HTML.strip
            👤 #{telegram_user_link(attributes)}
            #{html(t(:role_label, role: attributes.fetch("role")))}
          HTML
          candidate = "#{messages.last}\n\n#{block}"
          candidate.bytesize > Bot::MESSAGE_LIMIT ? messages << block : messages[-1] = candidate
        end
        messages
      end

      def price_application_text_with_links(proposal, users:, locale:)
        lines = [html(t(:prices_title, locale: locale)), "💵 USDT", ""]
        proposal.each do |entry|
          attributes = entry.fetch("attributes")
          lines << "#{attributes.fetch("position")}. #{html(attributes.fetch("name"))} · #{html(entry.fetch("id"))}"

          previous = attributes["previous_amount_usdt"]
          current = attributes["current_amount_usdt"]
          lines << "   ⏮ #{html(previous)} → 💰 #{html(current)} USDT" if previous || current

          editor_id = attributes["current_edited_by_user_id"]
          editor = users[editor_id.to_s] || legacy_editor_link(attributes)
          lines << "   ✏️ #{editor}" if editor

          applied_at = attributes["current_applied_at"]
          lines << "   🕒 #{html(TimestampFormatter.format(applied_at))}" if applied_at
          lines << ""
        end
        lines << html(t(:update_single_price, locale: locale))
        lines << html(t(:review_prices, locale: locale))
        lines.join("\n").strip
      end

      def legacy_editor_link(attributes)
        username = attributes["current_edited_by_username"] ||
                   attributes["current_edited_by_telegram_username"]
        telegram_id = attributes["current_edited_by_telegram_user_id"]
        return telegram_user_link("telegram_username" => username, "telegram_user_id" => telegram_id) if username || telegram_id

        nil
      end

      def telegram_user_link(attributes)
        username = clean(attributes["telegram_username"] || attributes["username"])&.delete_prefix("@")
        telegram_id = clean(attributes["telegram_user_id"] || attributes["user_id"])
        first_name = clean(attributes["telegram_first_name"] || attributes["first_name"])
        last_name = clean(attributes["telegram_last_name"] || attributes["last_name"])
        full_name = [first_name, last_name].compact.join(" ")

        if username
          %(<a href="https://t.me/#{html(username)}">@#{html(username)}</a>)
        elsif telegram_id
          label = full_name.empty? ? telegram_id : full_name
          %(<a href="tg://user?id=#{html(telegram_id)}">#{html(label)}</a>)
        elsif !full_name.empty?
          html(full_name)
        else
          html(t(:no_username))
        end
      end

      def send_html_message(chat_id, text)
        parameters = @telegram_api.method(:send_message).parameters
        accepts_parse_mode = parameters.any? do |kind, name|
          kind == :keyrest || %i[key keyreq].include?(kind) && name == :parse_mode
        end
        return @telegram_api.send_message(chat_id: chat_id, text: text, parse_mode: "HTML") if accepts_parse_mode

        @telegram_api.send_message(chat_id: chat_id, text: text)
      end

      def html(value)
        CGI.escapeHTML(value.to_s)
      end

      def clean(value)
        value = value.to_s.strip
        value.empty? ? nil : value
      end
    end

    Bot.prepend(TelegramUserLinks)
  end
end
