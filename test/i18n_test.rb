# frozen_string_literal: true

require_relative "test_helper"
require "zero_x_da/market_client_bot/i18n"

class I18nTest < Minitest::Test
  Locale = ZeroXDA::MarketClientBot::Locale
  I18n = ZeroXDA::MarketClientBot::I18n

  def test_language_variants_resolve_to_supported_locales
    expectations = {
      "en" => "en_US",
      "en-GB" => "en_US",
      "en_AU" => "en_US",
      "uk-UA" => "uk_UA",
      "ru-KZ" => "ru_RU",
      "fr-CA" => "fr_FR",
      "fr_BE" => "fr_FR",
      "es-MX" => "es_ES",
      "es_AR" => "es_ES",
      "de-AT" => "de_DE",
      "de_CH" => "de_DE"
    }

    expectations.each do |input, expected|
      assert_equal expected, Locale.resolve(input), input
      assert_equal expected, Locale.normalize(input), input
    end
  end

  def test_unknown_language_falls_back_to_english
    assert_equal "en_US", Locale.resolve("pt-BR")
    assert_equal "en_US", Locale.normalize("ja_JP")
  end

  def test_every_locale_has_the_same_keys_as_english
    expected = I18n::TRANSLATIONS.fetch(Locale::DEFAULT).keys.sort

    I18n::TRANSLATIONS.each do |locale, translations|
      assert_equal expected, translations.keys.sort, locale
    end
  end

  def test_translation_uses_language_variant_and_interpolation
    assert_equal "👥 Utilisateurs actifs : 3", I18n.translate(:active_users_title, locale: "fr-CA", count: 3)
    assert_equal "Der Server wird gestartet…", I18n.translate(:server_starting, locale: "de-CH")
  end
end
