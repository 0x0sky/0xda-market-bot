# frozen_string_literal: true

module ZeroXDA
  module MarketClientBot
    Bot.send(:remove_const, :SERVER_START_NOTICE)
    Bot.const_set(:SERVER_START_NOTICE, "сервер запускається…")
  end
end
