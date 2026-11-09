# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SmallPict Models" do
  describe SmallPict::Models::OptimizeOptions do
    it "constructs valid options hash" do
      opts = described_class.new(
        format:          "avif",
        quality:         85,
        max_width:       1920,
        max_height:      1080,
        max_dimension:   1600,
        mode:            SmallPict::Mode::EXTREME,
        strip_metadata:  true,
        filename:        "hero.png",
        idempotency_key: "idemp_123"
      )

      hash = opts.to_h
      expect(hash[:format]).to eq("avif")
      expect(hash[:quality]).to eq(85)
      expect(hash[:max_width]).to eq(1920)
      expect(hash[:max_height]).to eq(1080)
      expect(hash[:max_dimension]).to eq(1600)
      expect(hash).not_to have_key(:fit)
      expect(hash[:mode]).to eq("extreme")
      expect(hash).not_to have_key(:lossless)
      expect(opts.idempotency_key).to eq("idemp_123")
    end
  end

  describe SmallPict::Models::OptimizeResult do
    it "calculates savings metrics correctly" do
      res = described_class.new(
        job_id:          "job_123",
        status:          "completed",
        url:             "https://cdn.smallpict.app/opt/hero.avif",
        format:          "avif",
        original_size:   100_000,
        compressed_size: 15_000
      )

      expect(res.job_id).to eq("job_123")
      expect(res.bytes_saved).to eq(85_000)
      expect(res.savings_percentage).to eq(85.0)
    end
  end

  describe SmallPict::Models::QuotaResponse do
    it "parses quota attributes" do
      quota = described_class.new(
        plan:              "api_velocity",
        bytes_used:        5_000_000,
        quota_limit:       10_000_000,
        active_keys_count: 3
      )

      expect(quota.plan).to eq("api_velocity")
      expect(quota.quota_percentage).to eq(50.0)
      expect(quota.active_keys_count).to eq(3)
    end
  end
end
