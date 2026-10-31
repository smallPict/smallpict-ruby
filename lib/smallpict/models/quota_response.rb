# frozen_string_literal: true

module SmallPict
  module Models
    class QuotaResponse
      attr_reader :plan, :bytes_used, :quota_limit, :quota_percentage,
                  :cdn_egress_used_bytes, :cdn_egress_quota_bytes,
                  :active_keys_count, :active_sites_count, :capacity

      def initialize(attributes = {})
        @plan                   = attributes[:plan] || attributes["plan"] || "free"
        @bytes_used             = (attributes[:bytes_used] || attributes["bytes_used"] || 0).to_i
        @quota_limit            = (attributes[:quota_limit] || attributes["quota_limit"] || 0).to_i
        @quota_percentage       = (attributes[:quota_percentage] || attributes["quota_percentage"] || calculate_percentage).to_f.round(2)
        @cdn_egress_used_bytes  = attributes[:cdn_egress_used_bytes] || attributes["cdn_egress_used_bytes"]
        @cdn_egress_quota_bytes = attributes[:cdn_egress_quota_bytes] || attributes["cdn_egress_quota_bytes"]
        @active_keys_count      = attributes[:active_keys_count] || attributes["active_keys_count"]
        @active_sites_count     = attributes[:active_sites_count] || attributes["active_sites_count"]
        # nil when the server could not read capacity, and from older servers that omit it.
        @capacity               = Capacity.from_hash(attributes[:capacity] || attributes["capacity"])
      end

      private

      def calculate_percentage
        return 0.0 if @quota_limit.zero?

        ((@bytes_used.to_f / @quota_limit) * 100.0).round(2)
      end
    end
  end
end
