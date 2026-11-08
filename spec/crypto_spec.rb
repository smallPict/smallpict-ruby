# frozen_string_literal: true

require "spec_helper"

RSpec.describe SmallPict::Crypto do
  describe ".sha256_hex" do
    it "returns the standard empty sha256 for empty data" do
      expect(described_class.sha256_hex("")).to eq(SmallPict::Crypto::EMPTY_SHA256)
      expect(described_class.sha256_hex(nil)).to eq(SmallPict::Crypto::EMPTY_SHA256)
    end

    it "computes correct sha256 hex string" do
      expect(described_class.sha256_hex("hello world")).to eq("b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    end
  end

  describe ".build_string_to_sign" do
    it "constructs the OpenAPI 3.1 canonical string to sign" do
      res = described_class.build_string_to_sign("POST", "/v1/optimize", "1716301234", SmallPict::Crypto::EMPTY_SHA256)
      expect(res).to eq("POST\n/v1/optimize\n1716301234\n#{SmallPict::Crypto::EMPTY_SHA256}")
    end
  end

  describe ".hmac_sha256_hex" do
    it "produces a valid 64-char hex HMAC signature" do
      sts = described_class.build_string_to_sign("POST", "/v1/optimize", "1716301234", SmallPict::Crypto::EMPTY_SHA256)
      sig = described_class.hmac_sha256_hex("sec_test_secret_123", sts)
      expect(sig.length).to eq(64)
      expect(sig).to match(/\A[a-f0-9]{64}\z/)
    end
  end
end

RSpec.describe SmallPict::Crypto, "known answers" do
  it "matches RFC 4231 test case 2" do
    expect(described_class.hmac_sha256_hex("Jefe", "what do ya want for nothing?"))
      .to eq("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
  end

  it "signs the documented string-to-sign" do
    sts = described_class.build_string_to_sign(:post, "/v1/optimize", "1716301234", SmallPict::Crypto::EMPTY_SHA256)
    expect(sts).to eq("POST\n/v1/optimize\n1716301234\n#{SmallPict::Crypto::EMPTY_SHA256}")
  end
end
