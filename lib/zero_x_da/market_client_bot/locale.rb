# frozen_string_literal: true

module ZeroXDA
  module MarketClientBot
    module Locale
      DEFAULT = "en_US"
      UKRAINIAN = "uk_UA"
      SUPPORTED = [DEFAULT, UKRAINIAN].freeze

      module_function

      def resolve(language_code)
        language_code.to_s.downcase.start_with?("uk") ? UKRAINIAN : DEFAULT
      end

      def normalize(locale)
        SUPPORTED.include?(locale.to_s) ? locale.to_s : DEFAULT
      end
    end
  end
end
