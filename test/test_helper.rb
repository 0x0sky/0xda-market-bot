$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"

class FakeMarketAPI
  attr_reader :requests,
              :health_requests,
              :product_requests,
              :product_locales,
              :price_proposal_requests,
              :applied_prices

  PRODUCTS = [
    ["premium_3m", "Premium 3m", "Telegram Premium 3 months", "Telegram Premium 3 міс.", "Premium 3 міс."],
    ["premium_6m", "Premium 6m", "Telegram Premium 6 months", "Telegram Premium 6 міс.", "Premium 6 міс."],
    ["premium_12m", "Premium 12m", "Telegram Premium 12 months", "Telegram Premium 12 міс.", "Premium 12 міс."],
    ["stars_500", "Stars 500", "Stars 500", "Stars 500", "Stars 500"],
    ["stars_1000", "Stars 1000", "Stars 1000", "Stars 1000", "Stars 1000"],
    ["stars_3000", "Stars 3000", "Stars 3000", "Stars 3000", "Stars 3000"],
    ["ton", "TON", "TON", "TON", "TON"],
    ["btc", "BTC", "BTC", "BTC", "BTC"],
    ["eth", "ETH", "ETH", "ETH", "ETH"]
  ].freeze

  def initialize
    @requests = []
    @health_requests = 0
    @product_requests = 0
    @product_locales = []
    @price_proposal_requests = []
    @applied_prices = []
  end

  def authenticate_telegram(user:, chat:)
    @requests << { user: user, chat: chat }
    role = user.fetch("id").to_s == "99" ? "admin" : "client"
    {
      "id" => "12345678-1234-4000-8000-123456789012",
      "attributes" => { "role" => role, "status" => "active" }
    }
  end

  def health
    @health_requests += 1
    { "status" => "ok", "server_time" => "2026-07-12T00:00:00.000000Z" }
  end

  def active_users
    [
      {
        "id" => "12345678-1234-4000-8000-123456789012",
        "attributes" => {
          "telegram_user_id" => "77",
          "role" => "client",
          "status" => "active",
          "locale" => "uk_UA"
        }
      }
    ]
  end

  def products(locale: "en_US")
    @product_requests += 1
    @product_locales << locale
    PRODUCTS.each_with_index.map do |(sku, short_name, english_name, ukrainian_name, ukrainian_button), index|
      ukrainian = locale == "uk_UA"
      {
        "type" => "product",
        "id" => sku,
        "attributes" => {
          "short_name" => short_name,
          "name" => ukrainian ? ukrainian_name : english_name,
          "button_label" => ukrainian ? ukrainian_button : short_name,
          "locale" => ukrainian ? "uk_UA" : "en_US",
          "status" => "active",
          "position" => index + 1
        }
      }
    end
  end

  def price_proposal(actor_telegram_user_id:, locale: "en_US")
    @price_proposal_requests << {
      actor_telegram_user_id: actor_telegram_user_id,
      locale: locale
    }
    products(locale: locale).first(2).map do |product|
      {
        "type" => "price",
        "id" => product.fetch("id"),
        "attributes" => {
          "name" => product.dig("attributes", "name"),
          "position" => product.dig("attributes", "position"),
          "previous_amount_usdt" => "7.20",
          "current_amount_usdt" => "7.45",
          "current_edited_by_user_id" => "12345678-1234-4000-8000-123456789012",
          "current_applied_at" => "2026-07-19T07:00:00.000000Z"
        }
      }
    end
  end

  def apply_prices(actor_telegram_user_id:, prices:)
    @applied_prices << { actor_telegram_user_id: actor_telegram_user_id, prices: prices }
    prices.map do |price|
      {
        "type" => "price",
        "id" => price.fetch(:sku),
        "attributes" => { "amount_usdt" => price.fetch(:amount_usdt) }
      }
    end
  end

  def set_admin(actor_telegram_user_id:, target:)
    @requests << {
      actor_telegram_user_id: actor_telegram_user_id,
      target: target
    }
    {
      "id" => "87654321-4321-4000-8000-210987654321",
      "attributes" => {
        "telegram_user_id" => "88",
        "telegram_chat_id" => "880",
        "role" => "admin",
        "status" => "active"
      },
      "meta" => { "changed" => true }
    }
  end
end

class FakeTelegramAPI
  attr_reader :messages, :command_sets, :deleted_messages, :answered_callbacks

  def initialize
    @messages = []
    @command_sets = []
    @deleted_messages = []
    @answered_callbacks = []
  end

  def send_message(chat_id:, text:, reply_markup: nil)
    message = {
      "message_id" => @messages.length + 1,
      chat_id: chat_id,
      text: text,
      reply_markup: reply_markup
    }
    @messages << message
    message
  end

  def answer_callback_query(callback_query_id:, text: nil)
    @answered_callbacks << { callback_query_id: callback_query_id, text: text }
  end

  def delete_message(chat_id:, message_id:)
    @deleted_messages << { chat_id: chat_id, message_id: message_id }
  end

  def set_commands(commands, scope: nil)
    @command_sets << { commands: commands, scope: scope }
  end
end
