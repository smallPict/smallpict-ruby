# frozen_string_literal: true

require "spec_helper"

RSpec.describe SmallPict::Error do
  describe ".sanitize" do
    it "masks api keys and secrets" do
      raw = "Invalid key sp_sdk_1234567890abcdef1234567890abcdef with sec_secret123456"
      sanitized = described_class.sanitize(raw)
      expect(sanitized).not_to include("sp_sdk_1234567890abcdef1234567890abcdef")
      expect(sanitized).not_to include("sec_secret123456")
      expect(sanitized).to include("sp_sdk_123...cdef")
      expect(sanitized).to include("***REDACTED***")
    end
  end

  describe "#to_s" do
    it "formats error with code, status, and request id" do
      err = SmallPict::AuthenticationError.new("Access denied with key sp_test_11223344556677889900", request_id: "req_001")
      str = err.to_s
      expect(str).not_to include("sp_test_11223344556677889900")
      expect(str).to include("[UNAUTHORIZED HTTP 401]")
      expect(str).to include("Request ID: req_001")
    end
  end

  describe "subclasses" do
    it "provides proper status codes and error codes" do
      expect(SmallPict::ValidationError.new.status_code).to eq(400)
      expect(SmallPict::AuthenticationError.new.status_code).to eq(401)
      expect(SmallPict::QuotaExceededError.new.status_code).to eq(402)
      expect(SmallPict::PermissionDeniedError.new.status_code).to eq(403)
      expect(SmallPict::NotFoundError.new.status_code).to eq(404)
      expect(SmallPict::RateLimitError.new.status_code).to eq(429)
      expect(SmallPict::ServerError.new.status_code).to eq(500)
      expect(SmallPict::TimeoutError.new.status_code).to eq(408)
    end
  end
end

RSpec.describe "credential redaction" do
  it "masks sps_ secret keys in error messages" do
    secret = "sps_#{"ab12" * 16}"
    expect(SmallPict::Error.sanitize("bad key #{secret}")).not_to include(secret)
  end

  it "does not print the keys when a client is inspected" do
    client = SmallPict::Client.new(api_key: "sp_sdk_test_1234567890", secret_key: "sps_1234567890abcdef1234567890abcdef")
    [client.inspect, client.to_s].each do |text|
      expect(text).not_to include("sp_sdk_test_1234567890")
      expect(text).not_to include("sps_1234567890abcdef1234567890abcdef")
    end
  end

  it "does not print the keys when the configuration is inspected" do
    SmallPict.configure do |c|
      c.api_key = "sp_sdk_test_1234567890"
      c.secret_key = "sps_1234567890abcdef1234567890abcdef"
    end
    [SmallPict.configuration.inspect, SmallPict.configuration.to_s].each do |text|
      expect(text).not_to include("sp_sdk_test_1234567890")
      expect(text).not_to include("sps_1234567890abcdef1234567890abcdef")
    end
  end
end
