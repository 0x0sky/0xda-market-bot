# frozen_string_literal: true

require_relative "test_helper"

class ProviderBoundaryTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_core_contract_translation_is_owned_by_market_api
    source = File.read(File.join(ROOT, "lib/zero_x_da/market_client_bot/market_api.rb"))

    assert_includes source, '"v1/auth/external"'
    assert_includes source, 'provider: TELEGRAM_PROVIDER'
    assert_includes source, 'actor_user_id:'
    assert_includes source, 'target_user_id:'
  end

  def test_telegram_specific_core_routes_are_not_called
    ruby_files.each do |path|
      source = File.read(path)
      refute_includes source, "/v1/auth/telegram", path
      refute_includes source, "actor_telegram_user_id:", path unless path.end_with?("market_api.rb")
    end
  end

  private

  def ruby_files
    Dir[File.join(ROOT, "lib/**/*.rb")].sort
  end
end
