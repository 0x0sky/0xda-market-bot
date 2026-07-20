# frozen_string_literal: true

require_relative "i18n"

module ZeroXDA
  module MarketClientBot
    module LocalizedServerStartNotice
      include I18n::Helpers

      private

      def with_server_start_notice(message)
        return yield unless supported_command?(message["text"])

        chat_id = message.fetch("chat").fetch("id")
        locale = locale_for(message)
        completed = false
        lock = Mutex.new
        notifier = Thread.new do
          sleep @server_start_notice_delay
          send_message(chat_id, t(:server_starting, locale: locale)) unless lock.synchronize { completed }
        rescue TelegramAPI::Error => error
          warn "server start notice failed: #{error.message}"
        end
        notifier.report_on_exception = false
        yield
      ensure
        if lock
          lock.synchronize { completed = true }
          notifier&.kill
        end
      end
    end

    module LocalizedLegacyCopy
      include I18n::Helpers

      private

      def send_message(chat_id, text, reply_markup: nil)
        localized_text = text == "доступ заборонено." ? t(:access_denied) : text
        super(chat_id, localized_text, reply_markup: reply_markup)
      end
    end

    Bot.prepend(LocalizedServerStartNotice)
    Bot.prepend(LocalizedLegacyCopy)
  end
end
