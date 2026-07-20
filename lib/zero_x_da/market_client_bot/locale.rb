# frozen_string_literal: true

module ZeroXDA
  module MarketClientBot
    module Locale
      DEFAULT = "en_US"
      UKRAINIAN = "uk_UA"
      RUSSIAN = "ru_RU"
      FRENCH = "fr_FR"
      SPANISH = "es_ES"
      GERMAN = "de_DE"

      LANGUAGE_MAP = {
        "en" => DEFAULT,
        "uk" => UKRAINIAN,
        "ru" => RUSSIAN,
        "fr" => FRENCH,
        "es" => SPANISH,
        "de" => GERMAN
      }.freeze
      SUPPORTED = LANGUAGE_MAP.values.uniq.freeze

      module_function

      def resolve(language_code)
        LANGUAGE_MAP.fetch(language_subtag(language_code), DEFAULT)
      end

      def normalize(locale)
        value = locale.to_s
        return value if SUPPORTED.include?(value)

        resolve(value)
      end

      def language_subtag(value)
        value.to_s.strip.downcase.split(/[-_]/, 2).first
      end
    end
  end
end
