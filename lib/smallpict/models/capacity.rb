# frozen_string_literal: true

module SmallPict
  module Models
    CapacityStorage = Data.define(:limit_bytes, :used_bytes, :base_bytes, :addon_blocks)
    CapacityCdn     = Data.define(:limit_bytes, :used_bytes, :status)
    CapacityBooster = Data.define(:active, :wp_quota_bytes, :api_transforms, :cdn_bytes, :next_expiry)
    CapacityExpiry  = Data.define(:kind, :units, :expires_at)
    CapacityLapse   = Data.define(:stage, :delete_after)

    # Read-only capacity of the key's product from GET /v1/quota. A member that
    # does not apply to the product or plan is nil. manage_url is a plain string:
    # the SDK never opens or fetches it; capacity is bought only in the dashboard.
    Capacity = Data.define(:period_end, :storage, :cdn, :booster, :lapse, :manage_url) do
      def self.from_hash(data)
        return nil unless data.is_a?(Hash)

        s  = get(data, :storage)
        cd = get(data, :cdn)
        b  = get(data, :booster) || {}
        e  = get(b, :next_expiry)
        l  = get(data, :lapse)
        new(
          period_end: get(data, :period_end),
          storage: s && CapacityStorage.new(limit_bytes: get(s, :limit_bytes), used_bytes: get(s, :used_bytes),
                                            base_bytes: get(s, :base_bytes), addon_blocks: get(s, :addon_blocks)),
          cdn: cd && CapacityCdn.new(limit_bytes: get(cd, :limit_bytes), used_bytes: get(cd, :used_bytes),
                                     status: get(cd, :status)),
          booster: CapacityBooster.new(
            active: get(b, :active) == true,
            wp_quota_bytes: get(b, :wp_quota_bytes),
            api_transforms: get(b, :api_transforms),
            cdn_bytes: get(b, :cdn_bytes),
            next_expiry: e && CapacityExpiry.new(kind: get(e, :kind), units: get(e, :units),
                                                 expires_at: get(e, :expires_at))
          ),
          lapse: l && CapacityLapse.new(stage: get(l, :stage), delete_after: get(l, :delete_after)),
          manage_url: get(data, :manage_url)
        )
      end

      # String keys from JSON, symbol keys from callers; keeps false and nil as sent.
      def self.get(hash, key)
        hash.is_a?(Hash) ? hash.fetch(key.to_s) { hash[key] } : nil
      end
    end
  end
end
