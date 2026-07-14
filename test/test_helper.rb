$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"

class FakeMarketAPI
  attr_reader :requests, :health_requests, :product_requests

  PRODUCTS = [
    ["premium_3m", "Telegram Premium 3 міс.", "Premium 3 міс."],
    ["premium_6m", "Telegram Premium 6 міс.", "Premium 6 міс."],
    ["premium_9m", "Telegram Premium 9 міс.", "Premium 9 міс."],
    ["stars_500", "Stars 500", "Stars 500"],
    ["stars_1000", "Stars 1000", "Stars 1000"],
    ["stars_3000", "Stars 3000", "Stars 3000"],
    ["ton", "TON", "TON"],
    ["btc", "BTC", "BTC"],
    ["eth", "ETH", "ETH"]
  ].each_with_index.map do |(sku, name, button_label), index|
    {
      "type" => "product",
      "id" => sku,
      "attributes" => {
        "name" => name,
        "button_label" => button_label,
        "status" => "active",
        "position" => index + 1
      }
    }
  end.freeze

  def initialize
    @requests = []
    @health_requests = 0
    @product_requests = 0
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
          "status" => "active"
        }
      }
    ]
  end

  def products
    @product_requests += 1
    PRODUCTS
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
