# frozen_string_literal: true

require "spec_helper"

# Cases copied from smallpict-sdk-shared/capacity.json (not available in CI).
BILLING = "https://smallpict.app/dashboard/billing"

RSpec.describe "capacity and upgrade links" do
  let(:base_url) { "https://api.smallpict.app" }
  let(:client) { SmallPict::Client.new(api_key: "sp_sdk_test_1234567890", secret_key: "sec_test_secret_123", base_url: base_url) }

  quota_responses = {
    "wordpress_with_capacity"       => {
      "plan" => "pro", "bytes_used" => 1_048_576,
      "capacity" => {
        "period_end" => "2026-11-30T00:00:00Z",
        "storage"    => { "limit_bytes" => 75_161_927_680, "used_bytes" => 7_516_192_768, "base_bytes" => 53_687_091_200,
                       "addon_blocks" => 2 },
        "cdn"        => { "limit_bytes" => 53_687_091_200, "used_bytes" => 44_023_414_784, "status" => "warn_80" },
        "booster"    => {
          "active" => true, "wp_quota_bytes" => 2_147_483_648, "api_transforms" => nil, "cdn_bytes" => 107_374_182_400,
          "next_expiry" => { "kind" => "cdn_bytes", "units" => 42_949_672_960, "expires_at" => "2027-01-05T00:00:00Z" }
        },
        "lapse"      => nil,
        "manage_url" => BILLING
      }
    },
    "api_blocked"                   => {
      "plan" => "velocity", "bytes_used" => 0,
      "capacity" => {
        "period_end" => nil,
        "storage"    => { "limit_bytes" => 107_374_182_400, "used_bytes" => 1_073_741_824,
                       "base_bytes" => 107_374_182_400, "addon_blocks" => 0 },
        "cdn"        => nil,
        "booster"    => { "active" => false, "wp_quota_bytes" => nil, "api_transforms" => 5000, "cdn_bytes" => nil,
                       "next_expiry" => nil },
        "lapse"      => { "stage" => "blocked", "delete_after" => "2027-01-28T00:00:00Z" },
        "manage_url" => BILLING
      }
    },
    "sandbox"                       => {
      "plan" => "sandbox", "bytes_used" => 0,
      "capacity" => {
        "period_end" => nil,
        "storage"    => nil,
        "cdn"        => { "limit_bytes" => 1_073_741_824, "used_bytes" => 0, "status" => "ok" },
        "booster"    => { "active" => false, "wp_quota_bytes" => nil, "api_transforms" => 0, "cdn_bytes" => 0,
                       "next_expiry" => nil },
        "lapse"      => nil,
        "manage_url" => BILLING
      }
    },
    "capacity_unreadable"           => { "plan" => "pro", "bytes_used" => 0, "capacity" => nil },
    "older_server_without_capacity" => { "plan" => "pro", "bytes_used" => 0 }
  }

  def quota_for(body)
    stub_request(:get, "#{base_url}/v1/quota")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(body))
    client.get_quota
  end

  it "parses every member of wordpress_with_capacity" do
    q = quota_for(quota_responses["wordpress_with_capacity"])
    expect(q.plan).to eq("pro")
    expect(q.bytes_used).to eq(1_048_576)
    c = q.capacity
    expect(c.period_end).to eq("2026-11-30T00:00:00Z")
    expect(c.storage.to_h).to eq(limit_bytes: 75_161_927_680, used_bytes: 7_516_192_768,
                                 base_bytes: 53_687_091_200, addon_blocks: 2)
    expect(c.cdn.to_h).to eq(limit_bytes: 53_687_091_200, used_bytes: 44_023_414_784, status: "warn_80")
    expect(c.booster.active).to be(true)
    expect(c.booster.wp_quota_bytes).to eq(2_147_483_648)
    expect(c.booster.api_transforms).to be_nil
    expect(c.booster.cdn_bytes).to eq(107_374_182_400)
    expect(c.booster.next_expiry.to_h).to eq(kind: "cdn_bytes", units: 42_949_672_960,
                                             expires_at: "2027-01-05T00:00:00Z")
    expect(c.lapse).to be_nil
    expect(c.manage_url).to eq(BILLING)
  end

  it "keeps nullable members nil (api_blocked)" do
    c = quota_for(quota_responses["api_blocked"]).capacity
    expect(c.period_end).to be_nil
    expect(c.cdn).to be_nil
    expect(c.storage.addon_blocks).to eq(0)
    expect(c.booster.to_h).to eq(active: false, wp_quota_bytes: nil, api_transforms: 5000, cdn_bytes: nil,
                                 next_expiry: nil)
    expect(c.lapse.to_h).to eq(stage: "blocked", delete_after: "2027-01-28T00:00:00Z")
  end

  it "keeps sandbox zeros as zeros and storage nil" do
    c = quota_for(quota_responses["sandbox"]).capacity
    expect(c.storage).to be_nil
    expect(c.cdn.to_h).to eq(limit_bytes: 1_073_741_824, used_bytes: 0, status: "ok")
    expect(c.booster.api_transforms).to eq(0)
    expect(c.booster.cdn_bytes).to eq(0)
    expect(c.booster.active).to be(false)
  end

  it "returns nil capacity when the server sends null" do
    q = quota_for(quota_responses["capacity_unreadable"])
    expect(q.capacity).to be_nil
    expect(q.plan).to eq("pro")
  end

  it "parses a response without capacity (older server)" do
    q = quota_for(quota_responses["older_server_without_capacity"])
    expect(q.capacity).to be_nil
    expect(q.plan).to eq("pro")
    expect(q.bytes_used).to eq(0)
  end

  error_cases = [
    { status: 402, code: "QUOTA_EXCEEDED", klass: SmallPict::QuotaExceededError,
      details: { "upgrade_url" => BILLING }, upgrade_url: BILLING },
    { status: 402, code: "storage_quota_exceeded", klass: SmallPict::QuotaExceededError,
      details: { "limit_bytes" => 10, "used_bytes" => 10, "remaining_bytes" => 0, "upgrade_url" => BILLING },
      upgrade_url: BILLING },
    { status: 402, code: "account_read_only", klass: SmallPict::QuotaExceededError,
      details: { "delete_after" => "2027-01-28T00:00:00Z", "upgrade_url" => BILLING },
      upgrade_url: BILLING },
    { status: 402, code: "QUOTA_EXCEEDED", klass: SmallPict::QuotaExceededError,
      details: { "payload_bytes" => 60_000_000 }, upgrade_url: nil },
    { status: 403, code: "mode_not_in_plan", klass: SmallPict::PermissionDeniedError,
      details: { "mode" => "extreme", "allowed_modes" => %w[lossy lossless] },
      allowed_modes: %w[lossy lossless], upgrade_url: nil },
    { status: 409, code: "booster_period_limit_exceeded", klass: SmallPict::Error,
      details: { "remaining_steps" => 0, "upgrade_url" => BILLING },
      upgrade_url: BILLING }
  ]

  error_cases.each do |tc|
    it "maps #{tc[:status]} #{tc[:code]} to #{tc[:klass]} with upgrade_url #{tc[:upgrade_url].inspect}" do
      stub_request(:get, "#{base_url}/v1/quota").to_return(
        status: tc[:status], headers: { "Content-Type" => "application/json" },
        body: JSON.generate(error: { code: tc[:code], message: "capacity", details: tc[:details] })
      )

      expect { client.get_quota }.to raise_error(tc[:klass]) { |e|
        expect(e.class).to eq(tc[:klass])
        expect(e.upgrade_url).to eq(tc[:upgrade_url])
        expect(e.details).to eq(tc[:details])
        expect(e.allowed_modes).to eq(tc[:allowed_modes]) if tc[:klass] == SmallPict::PermissionDeniedError
        if tc[:status] == 409
          expect(e.code).to eq(tc[:code])
          expect(e.status_code).to eq(409)
        end
      }
    end
  end

  it "does not expose a non-string upgrade_url" do
    err = SmallPict::QuotaExceededError.new("x", details: { "upgrade_url" => { "href" => "https://evil.example" } })
    expect(err.upgrade_url).to be_nil
  end

  it "has nil upgrade_url and allowed_modes without details" do
    err = SmallPict::PermissionDeniedError.new
    expect(err.upgrade_url).to be_nil
    expect(err.allowed_modes).to be_nil
  end

  it "does not retry or fetch upgrade_url" do
    stub_request(:get, "#{base_url}/v1/quota").to_return(
      status: 402, body: JSON.generate(error: { code:    "QUOTA_EXCEEDED",
                                                details: { upgrade_url: "#{base_url}/upgrade" } })
    )
    expect { client.get_quota }.to raise_error(SmallPict::QuotaExceededError)
    expect(a_request(:get, "#{base_url}/upgrade")).not_to have_been_made
  end
end
