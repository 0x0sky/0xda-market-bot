$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"

class FakeMarketAPI
  attr_reader :requests

  def initialize
    @requests = []
  end

  def authenticate_telegram(user:, chat:)
    @requests << { user: user, chat: chat }
    {
      "id" => "12345678-1234-4000-8000-123456789012",
      "attributes" => { "role" => "client", "status" => "active" }
    }
  end
end

class FakeTelegramAPI
  attr_reader :messages

  def initialize
    @messages = []
  end

  def send_message(chat_id:, text:)
    @messages << { chat_id: chat_id, text: text }
  end
end
