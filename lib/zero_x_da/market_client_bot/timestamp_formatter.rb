# frozen_string_literal: true

require "time"

module ZeroXDA
  module MarketClientBot
    module TimestampFormatter
      module_function

      def format(value)
        time = parse(value)
        return "—" unless time

        time.utc.strftime("%d.%m.%Y · %H:%M:%S UTC")
      end

      def parse(value)
        case value
        when Time then value
        when String then Time.iso8601(value)
        end
      rescue ArgumentError
        nil
      end
    end
  end
end
