# frozen_string_literal: true

require "time"
require_relative "market_api"
require_relative "telegram_api"
require_relative "price_messages"
require_relative "locale"

module ZeroXDA
  module MarketClientBot
    class Bot
      MESSAGE_LIMIT = 3_800
      SERVER_START_NOTICE = "0xda-market запускається…"
      SERVER_START_NOTICE_DELAY = 3
      STATUS_MESSAGE_TTL = 3
      CATALOG_PAGE_SIZE = 9
      CATALOG_COLUMNS = 3
      BUY_CALLBACK_PATTERN = /\Abuy_([a-z0-9][a-z0-9_-]{0,59})\z/
      APPLY_PRICE_CALLBACK_PATTERN = /\Aapplyprice_([a-z0-9][a-z0-9_-]{0,59})\z/
      PRICE_AMOUNT_PATTERN = /\A\d+(?:\.\d{1,6})?\z/
      CURRENCY_INPUT_PATTERN = /\A[A-Za-z][A-Za-z0-9]{2,9}\z/
      PRICE_DIALOG_TTL = 600
      START_COMMANDS = [
        { command: "start", description: "авторизація" }
      ].freeze
      CLIENT_COMMANDS = [
        { command: "buy", description: "купити" },
        { command: "status", description: "власний статус" }
      ].freeze
      ADMIN_COMMANDS = [
        *CLIENT_COMMANDS,
        { command: "servers", description: "стан серверів" },
        { command: "users", description: "активні користувачі" },
        { command: "setadmin", description: "призначити адміністратора" },
        { command: "apply_prices", description: "price application form" },
        { command: "apply_price", description: "set product price (USDT)" },
        { command: "rates", description: "fx rates (USDT base)" },
        { command: "set_rate", description: "set fx rate: CUR usdt_per_unit" }
      ].freeze
      SUPPORTED_COMMANDS = %w[
        /start /status /buy /servers /users /setadmin /apply_prices /apply_price /rates /set_rate
      ].freeze

      def initialize(
        market_api:,
        telegram_api:,
        clock: -> { Time.now.utc },
        server_start_notice_delay: SERVER_START_NOTICE_DELAY,
        status_message_ttl: STATUS_MESSAGE_TTL
      )
        @market_api = market_api
        @telegram_api = telegram_api
        @clock = clock
        @server_start_notice_delay = server_start_notice_delay
        @status_message_ttl = status_message_ttl
        @price_dialogs = {}
        @price_dialogs_lock = Mutex.new
      end

      def handle(update)
        message = update["message"]
        callback = update["callback_query"]
        return handle_callback(callback) if callback
        return unless message

        command, argument = parse_command(message["text"])
        if command
          clear_price_dialog(message.fetch("chat").fetch("id"))
          with_server_start_notice(message) do
            case command
            when "/start"
              authenticate(message)
            when "/status"
              show_status(message)
            when "/buy"
              show_products(message)
            when "/servers"
              show_servers(message)
            when "/users"
              show_active_users(message)
            when "/setadmin"
              set_admin(message, argument)
            when "/apply_prices"
              start_price_application(message)
            when "/apply_price"
              apply_single_price(message, argument)
            when "/rates"
              show_fx_rates(message)
            when "/set_rate"
              set_fx_rate(message, argument)
            end
          end
        elsif message["text"] && price_dialog_for(message)
          continue_price_dialog(message)
        end
      rescue KeyError, ArgumentError, MarketAPI::Error => error
        notify_failure(message || callback&.fetch("message", nil), error)
      end

      private

      def with_server_start_notice(message)
        return yield unless supported_command?(message["text"])

        chat_id = message.fetch("chat").fetch("id")
        completed = false
        lock = Mutex.new
        notifier = Thread.new do
          sleep @server_start_notice_delay
          send_message(chat_id, SERVER_START_NOTICE) unless lock.synchronize { completed }
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

      def supported_command?(text)
        SUPPORTED_COMMANDS.include?(parse_command(text).first)
      end

      def parse_command(text)
        match = text.to_s.match(%r{\A(/\w+)(?:@\w+)?(?:\s+(.+)|\z)})
        [match&.[](1)&.downcase, match&.[](2)&.strip]
      end

      def authenticate(message)
        chat = message.fetch("chat")
        user = @market_api.authenticate_telegram(
          user: message.fetch("from"),
          chat: chat
        )
        chat_id = chat.fetch("id")
        sync_commands(chat_id, user)
        send_status_message(chat_id, user)
      end

      def show_status(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        send_status_message(chat_id, user)
      end

      def show_products(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        products = @market_api.products(locale: locale_for(message))
        send_message(
          chat_id,
          "обери продукт для купівлі:",
          reply_markup: catalog_keyboard(products, callback_prefix: "buy")
        )
      end

      def handle_callback(callback)
        data = callback.fetch("data").to_s
        if (match = BUY_CALLBACK_PATTERN.match(data))
          handle_buy_callback(callback, match[1])
        elsif (match = APPLY_PRICE_CALLBACK_PATTERN.match(data))
          handle_apply_price_callback(callback, match[1])
        end
      end

      def handle_buy_callback(callback, sku)
        message = callback.fetch("message")
        chat_id = message.fetch("chat").fetch("id")
        user = @market_api.authenticate_telegram(
          user: callback.fetch("from"),
          chat: message.fetch("chat")
        )
        sync_commands(chat_id, user)
        product = find_product_by_sku(sku, locale: locale_for(callback))
        raise ArgumentError, "product is unavailable" unless product

        @telegram_api.answer_callback_query(
          callback_query_id: callback.fetch("id"),
          text: "обрано: #{product.dig("attributes", "name")}"
        )
      end

      def handle_apply_price_callback(callback, sku)
        message = callback.fetch("message")
        chat_id = message.fetch("chat").fetch("id")
        user = @market_api.authenticate_telegram(
          user: callback.fetch("from"),
          chat: message.fetch("chat")
        )
        sync_commands(chat_id, user)
        unless admin?(user)
          @telegram_api.answer_callback_query(callback_query_id: callback.fetch("id"))
          return send_message(chat_id, "доступ заборонено.")
        end

        locale = locale_for(callback)
        product = find_product_by_sku(sku, locale: locale)
        raise ArgumentError, "product is unavailable" unless product

        request_price_amount(
          chat_id: chat_id,
          user_id: callback.fetch("from").fetch("id"),
          product: product,
          locale: locale
        )
        @telegram_api.answer_callback_query(
          callback_query_id: callback.fetch("id"),
          text: "обрано: #{product.dig("attributes", "name")}"
        )
      end

      def find_product_by_sku(sku, locale:)
        @market_api.products(locale: locale).find do |entry|
          entry.fetch("id") == sku
        end
      end

      def catalog_keyboard(products, callback_prefix:)
        buttons = products.first(CATALOG_PAGE_SIZE).map do |product|
          {
            text: product.dig("attributes", "button_label") || product.dig("attributes", "name"),
            callback_data: "#{callback_prefix}_#{product.fetch("id")}"
          }
        end
        { inline_keyboard: buttons.each_slice(CATALOG_COLUMNS).to_a }
      end

      def show_servers(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, "доступ заборонено.") unless admin?(user)

        health = @market_api.health
        core_status = health.fetch("status", "unknown")
        core_time = health.fetch("server_time", "—")
        bot_time = timestamp(@clock.call)
        text = <<~TEXT.strip
          zeroxda-market / servers

          market core: #{status_label(core_status)}
          core time: #{core_time}

          client bot: ok ✅
          bot time: #{bot_time}
        TEXT
        send_message(chat_id, text)
      end

      def show_active_users(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, "доступ заборонено.") unless admin?(user)

        users = @market_api.active_users
        user_messages(users).each do |text|
          send_message(chat_id, text)
        end
      end

      def set_admin(message, target)
        chat_id = message.fetch("chat").fetch("id")
        actor = authenticate_user(message)
        sync_commands(chat_id, actor)
        return send_message(chat_id, "доступ заборонено.") unless admin?(actor)
        if target.to_s.empty?
          return send_message(chat_id, "формат: /setadmin @username або Telegram ID")
        end

        assignment = @market_api.set_admin(
          actor_telegram_user_id: message.fetch("from").fetch("id"),
          target: target
        )
        attributes = assignment.fetch("attributes")
        target_chat_id = attributes["telegram_chat_id"]
        sync_admin_target(target_chat_id, chat_id)
        text = <<~TEXT.strip
          admin призначений ✅

          telegram: #{attributes.fetch("telegram_user_id")}
          uuid: #{assignment.fetch("id")}
          role: #{attributes.fetch("role")}
        TEXT
        send_message(chat_id, text)
      end

      # /apply_prices — a new application over all prices. Sends the form:
      # yesterday's and current amounts per product plus instructions. Until a
      # new application is submitted, the last applied prices remain in effect.
      def start_price_application(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, "доступ заборонено.") unless admin?(user)

        locale = locale_for(message)
        proposal = @market_api.price_proposal(
          actor_telegram_user_id: message.fetch("from").fetch("id"),
          locale: locale
        )
        send_message(chat_id, PriceMessages.application_text(proposal, locale: locale))
      end

      # /apply_price <sku|position|short name> <amount in USDT>. Missing or
      # invalid parts fall back to a short dialog: first the product (typed or
      # picked from the catalog keyboard), then the amount.
      def apply_single_price(message, argument)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, "доступ заборонено.") unless admin?(user)

        locale = locale_for(message)
        user_id = message.fetch("from").fetch("id")
        parts = argument.to_s.split(/\s+/)
        if parts.empty?
          return request_product_selection(chat_id: chat_id, user_id: user_id, locale: locale)
        end

        amount = parts.last if parts.length >= 2 && parts.last.match?(PRICE_AMOUNT_PATTERN)
        reference = (amount ? parts[0..-2] : parts).join(" ")
        product = resolve_product(reference, locale: locale)

        if product && amount
          perform_price_application(
            chat_id: chat_id,
            actor_telegram_user_id: user_id,
            sku: product.fetch("id"),
            name: product.dig("attributes", "name"),
            amount: amount
          )
        elsif product
          request_price_amount(chat_id: chat_id, user_id: user_id, product: product, locale: locale)
        elsif amount.nil? && parts.length >= 2 &&
              (product = resolve_product(parts[0..-2].join(" "), locale: locale))
          send_message(chat_id, PriceMessages.invalid_amount(locale: locale))
          request_price_amount(chat_id: chat_id, user_id: user_id, product: product, locale: locale)
        else
          send_message(chat_id, PriceMessages.product_not_found(reference, locale: locale))
          request_product_selection(chat_id: chat_id, user_id: user_id, locale: locale)
        end
      end

      # /rates — all fx rates in the USDT base with the buy-side semantics:
      # how many USDT we pay for one unit of the currency.
      def show_fx_rates(message)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, "доступ заборонено.") unless admin?(user)

        rates = @market_api.fx_rates
        lines = ["0xda-market / fx rates", "usdt paid per 1 unit (buy side)", ""]
        rates.each do |rate|
          attributes = rate.fetch("attributes")
          lines << "#{attributes.fetch("currency")}: #{attributes.fetch("usdt_per_unit")}"
        end
        lines << ""
        lines << "Set a rate: /set_rate <currency> <usdt per 1 unit>"
        lines << "Example: /set_rate EUR 1.16"
        send_message(chat_id, lines.join("\n"))
      end

      # /set_rate <currency> <usdt per 1 unit>
      def set_fx_rate(message, argument)
        chat_id = message.fetch("chat").fetch("id")
        user = authenticate_user(message)
        sync_commands(chat_id, user)
        return send_message(chat_id, "доступ заборонено.") unless admin?(user)

        currency, value = argument.to_s.split(/\s+/, 2)
        value = value&.strip
        unless currency&.match?(CURRENCY_INPUT_PATTERN) && value&.match?(PRICE_AMOUNT_PATTERN)
          return send_message(
            chat_id,
            "format: /set_rate <currency> <usdt per 1 unit>\nexample: /set_rate EUR 1.16"
          )
        end

        applied = @market_api.set_fx_rates(
          actor_telegram_user_id: message.fetch("from").fetch("id"),
          rates: [{ currency: currency.upcase, usdt_per_unit: value }]
        )
        rate = applied.first
        send_message(
          chat_id,
          "rate applied ✅\n1 #{rate.fetch("id")} = #{rate.dig("attributes", "usdt_per_unit")} USDT"
        )
      end

      def request_product_selection(chat_id:, user_id:, locale:)
        products = @market_api.products(locale: locale)
        store_price_dialog(chat_id, user_id: user_id, step: :product)
        send_message(
          chat_id,
          PriceMessages.choose_product(locale: locale),
          reply_markup: catalog_keyboard(products, callback_prefix: "applyprice")
        )
      end

      def request_price_amount(chat_id:, user_id:, product:, locale:)
        store_price_dialog(
          chat_id,
          user_id: user_id,
          step: :amount,
          sku: product.fetch("id"),
          name: product.dig("attributes", "name")
        )
        send_message(
          chat_id,
          PriceMessages.enter_amount(product.dig("attributes", "name"), locale: locale)
        )
      end

      def continue_price_dialog(message)
        chat_id = message.fetch("chat").fetch("id")
        dialog = price_dialog_for(message)
        return unless dialog

        user = authenticate_user(message)
        unless admin?(user)
          clear_price_dialog(chat_id)
          return send_message(chat_id, "доступ заборонено.")
        end

        locale = locale_for(message)
        text = message["text"].to_s.strip
        case dialog.fetch(:step)
        when :product
          product = resolve_product(text, locale: locale)
          if product
            request_price_amount(
              chat_id: chat_id,
              user_id: dialog.fetch(:user_id),
              product: product,
              locale: locale
            )
          else
            send_message(chat_id, PriceMessages.product_not_found(text, locale: locale))
          end
        when :amount
          if text.match?(PRICE_AMOUNT_PATTERN)
            perform_price_application(
              chat_id: chat_id,
              actor_telegram_user_id: message.fetch("from").fetch("id"),
              sku: dialog.fetch(:sku),
              name: dialog.fetch(:name),
              amount: text
            )
          else
            send_message(chat_id, PriceMessages.invalid_amount(locale: locale))
          end
        end
      end

      def perform_price_application(chat_id:, actor_telegram_user_id:, sku:, name:, amount:)
        applied = @market_api.apply_prices(
          actor_telegram_user_id: actor_telegram_user_id,
          prices: [{ sku: sku, amount_usdt: amount }]
        )
        clear_price_dialog(chat_id)
        price = applied.first
        send_message(
          chat_id,
          "price applied ✅\n" \
          "#{name} (#{sku})\n" \
          "#{price.dig("attributes", "amount_usdt")} USDT"
        )
      end

      def store_price_dialog(chat_id, **state)
        @price_dialogs_lock.synchronize do
          @price_dialogs[chat_id] = state.merge(expires_at: @clock.call + PRICE_DIALOG_TTL)
        end
      end

      def price_dialog_for(message)
        chat_id = message.fetch("chat").fetch("id")
        @price_dialogs_lock.synchronize do
          dialog = @price_dialogs[chat_id]
          next nil unless dialog

          if dialog.fetch(:expires_at) < @clock.call
            @price_dialogs.delete(chat_id)
            next nil
          end
          next nil unless dialog.fetch(:user_id) == message.dig("from", "id")

          dialog
        end
      end

      def clear_price_dialog(chat_id)
        @price_dialogs_lock.synchronize { @price_dialogs.delete(chat_id) }
      end

      def resolve_product(reference, locale:)
        products = @market_api.products(locale: locale)
        normalized = reference.to_s.downcase.strip
        products.find { |product| product.fetch("id") == normalized } ||
          products.find { |product| product.dig("attributes", "position").to_s == normalized } ||
          fuzzy_product_match(products, normalized)
      end

      # Best-effort short-name matching: every token of the reference must
      # prefix a word of the product's sku, name, or button label. Ambiguous
      # references resolve to nothing rather than to a wrong product.
      def fuzzy_product_match(products, reference)
        tokens = reference.split(/[^a-z0-9]+/).reject(&:empty?)
        return nil if tokens.empty?

        matches = products.select do |product|
          haystack = [
            product.fetch("id"),
            product.dig("attributes", "short_name"),
            product.dig("attributes", "name"),
            product.dig("attributes", "button_label")
          ].compact.join(" ").downcase
          words = haystack.split(/[^[:alnum:]]+/).reject(&:empty?)
          tokens.all? do |token|
            haystack.include?(token) || words.any? { |word| word.start_with?(token) }
          end
        end
        matches.length == 1 ? matches.first : nil
      end

      def authenticate_user(message)
        @market_api.authenticate_telegram(
          user: message.fetch("from"),
          chat: message.fetch("chat")
        )
      end

      def locale_for(update)
        Locale.resolve(update.fetch("from", {})["language_code"])
      end

      def sync_commands(chat_id, user)
        commands = admin?(user) ? ADMIN_COMMANDS : CLIENT_COMMANDS
        @telegram_api.set_commands(
          commands,
          scope: { type: "chat", chat_id: chat_id }
        )
      rescue TelegramAPI::Error => error
        warn "command menu sync failed: #{error.message}"
      end

      def sync_admin_target(target_chat_id, actor_chat_id)
        return if target_chat_id.to_s.empty?

        @telegram_api.set_commands(
          ADMIN_COMMANDS,
          scope: { type: "chat", chat_id: target_chat_id }
        )
        return if target_chat_id.to_s == actor_chat_id.to_s

        send_message(target_chat_id, "вам призначено роль admin ✅")
      rescue TelegramAPI::Error => error
        warn "new admin menu sync failed: #{error.message}"
      end

      def admin?(user)
        user.dig("attributes", "role") == "admin"
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

      def user_status_message(user)
        role = client_role(user)
        status = user.dig("attributes", "status")
        indicator = status == "active" ? "✅" : "❌"
        <<~TEXT.strip
          авторизація успішна ✅
          role: #{role}
          status: #{status} #{indicator}
        TEXT
      end

      def send_status_message(chat_id, user)
        message = send_message(chat_id, user_status_message(user))
        schedule_message_deletion(chat_id, message)
      end

      def schedule_message_deletion(chat_id, message)
        message_id = message&.fetch("message_id", nil)
        return unless message_id

        delete = -> { @telegram_api.delete_message(chat_id: chat_id, message_id: message_id) }
        return delete.call if @status_message_ttl.zero?

        Thread.new do
          sleep @status_message_ttl
          delete.call
        rescue TelegramAPI::Error => error
          warn "status message deletion failed: #{error.message}"
        end.tap { |thread| thread.report_on_exception = false }
      end

      def status_label(status)
        status == "ok" ? "ok ✅" : "#{status} ❌"
      end

      def client_role(user)
        admin?(user) ? "admin" : "client"
      end

      def timestamp(value)
        raise ArgumentError, "clock must return a Time" unless value.is_a?(Time)

        value.utc.iso8601(6)
      end

      def send_message(chat_id, text, reply_markup: nil)
        @telegram_api.send_message(
          chat_id: chat_id,
          text: text,
          reply_markup: reply_markup
        )
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
