# frozen_string_literal: true

require "bundler/setup"
require "rack/common_logger"
require_relative "lib/zero_x_da/market_client_bot/bot"
require_relative "lib/zero_x_da/market_client_bot/market_api"
require_relative "lib/zero_x_da/market_client_bot/telegram_api"
require_relative "lib/zero_x_da/market_client_bot/web_app"

telegram_api = ZeroXDA::MarketClientBot::TelegramAPI.new(
  token: ENV.fetch("TELEGRAM_BOT_TOKEN")
)
market_api = ZeroXDA::MarketClientBot::MarketAPI.new(
  base_url: ENV.fetch("MARKET_API_URL", "https://zeroxda-market.onrender.com"),
  token: ENV.fetch("MARKET_API_TOKEN")
)
bot = ZeroXDA::MarketClientBot::Bot.new(
  market_api: market_api,
  telegram_api: telegram_api,
  admin_telegram_ids: ENV.fetch("ADMIN_TELEGRAM_IDS", "").split(",").map(&:strip)
)

use Rack::CommonLogger, $stdout

run ZeroXDA::MarketClientBot::WebApp.new(
  bot: bot,
  webhook_secret: ENV.fetch("TELEGRAM_WEBHOOK_SECRET")
)
