# frozen_string_literal: true

require "spec_helper"

RSpec.describe SmallPict::Client do
  let(:api_key) { "sp_sdk_test_1234567890" }
  let(:secret_key) { "sec_test_secret_123" }
  let(:base_url) { "https://api.smallpict.app" }
  let(:client) { described_class.new(api_key: api_key, secret_key: secret_key, base_url: base_url) }

  describe "#initialize" do
    it "raises ValidationError when api_key is missing" do
      expect { described_class.new(api_key: "") }.to raise_error(SmallPict::ValidationError)
    end
  end

  describe "#optimize" do
    it "sends optimization request and returns OptimizeResult" do
      stub_request(:post, "#{base_url}/v1/optimize")
        .with(
          headers: {
            "Accept"          => "application/json",
            "Content-Type"    => "application/json",
            "X-Api-Key"       => api_key
          }
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            job_id:             "job_rb_123",
            status:             "completed",
            url:                "https://cdn.smallpict.app/opt/photo.avif",
            format:             "avif",
            original_size:      100_000,
            compressed_size:    15_000,
            bytes_saved:        85_000,
            savings_percentage: 85.0
          })
        )

      result = client.optimize("fake image data", format: "avif", quality: 85)

      expect(result.job_id).to eq("job_rb_123")
      expect(result.status).to eq("completed")
      expect(result.url).to eq("https://cdn.smallpict.app/opt/photo.avif")
      expect(result.savings_percentage).to eq(85.0)
    end

    it "handles fallback passthrough on 402 quota exceeded" do
      stub_request(:post, "#{base_url}/v1/optimize")
        .to_return(
          status: 402,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            error: { code: "QUOTA_EXCEEDED", message: "Monthly quota full" }
          })
        )

      passthrough_client = described_class.new(
        api_key:       api_key,
        base_url:      base_url,
        fallback_mode: :passthrough
      )

      res = passthrough_client.optimize("raw binary test data", filename: "photo.jpg", mime_type: "image/jpeg")

      expect(res.job_id).to eq("fallback-passthrough")
      expect(res.status).to eq("completed")
      expect(res.savings_percentage).to eq(0.0)
    end

    # Cases from smallpict-sdk-shared/compression-modes.json (mapping_cases).
    context "compression mode mapping" do
      let(:ok_body) { JSON.generate({ job_id: "job_mode", status: "processing" }) }

      before do
        stub_request(:post, "#{base_url}/v1/optimize")
          .to_return(status: 202, headers: { "Content-Type" => "application/json" }, body: ok_body)
      end

      def sent_options
        options = nil
        expect(WebMock).to(have_requested(:post, "#{base_url}/v1/optimize").with do |req|
          options = JSON.parse(req.body)["options"]
        end)
        options
      end

      [
        ["no mode, no flag",       {},                                  nil],
        ["mode only",              { mode: "extreme" },                 "extreme"],
        ["deprecated flag only",   { lossless: true },                  "lossless"],
        ["flag false is ignored",  { lossless: false },                 nil],
        ["flag agrees with mode",  { mode: "lossless", lossless: true }, "lossless"]
      ].each do |name, input, wire_mode|
        it "#{name}: sends mode #{wire_mode.inspect} and never lossless" do
          client.optimize("img", **input)
          options = sent_options
          expect(options["mode"]).to eq(wire_mode)
          expect(options).not_to have_key("lossless")
          expect(options.key?("mode")).to eq(!wire_mode.nil?)
        end
      end

      it "flag contradicts mode: raises ValidationError without an HTTP call" do
        expect { client.optimize("img", mode: "lossy", lossless: true) }
          .to raise_error(SmallPict::ValidationError)
        expect(WebMock).not_to have_requested(:post, "#{base_url}/v1/optimize")
      end

      it "accepts the Mode constants" do
        expect(SmallPict::Mode::ALL).to eq(%w[lossy extreme lossless])
        expect(SmallPict::Mode::ALL).to be_frozen
        client.optimize("img", mode: SmallPict::Mode::LOSSLESS)
        expect(sent_options["mode"]).to eq("lossless")
      end

      it "warns that lossless is deprecated" do
        expect(Kernel).to receive(:warn).with(/deprecated/, category: :deprecated)
        client.optimize("img", lossless: true)
      end
    end

    it "raises PermissionDeniedError with details on 403 mode_not_in_plan" do
      stub_request(:post, "#{base_url}/v1/optimize")
        .to_return(
          status: 403,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            error: {
              code: "mode_not_in_plan",
              message: "Mode lossless is not included in your plan",
              details: { mode: "lossless", allowed_modes: %w[lossy extreme] }
            }
          })
        )

      expect { client.optimize("img", mode: "lossless") }.to raise_error(SmallPict::PermissionDeniedError) { |e|
        expect(e.message).to include("Mode lossless is not included in your plan")
        expect(e.details["mode"]).to eq("lossless")
        expect(e.details["allowed_modes"]).to eq(%w[lossy extreme])
      }
    end
  end

  describe "#get_job_status" do
    it "exposes mode_applied and quality_applied" do
      stub_request(:get, "#{base_url}/v1/optimize/status?job_id=job_1")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: JSON.generate({ job_id: "job_1", status: "completed", mode_applied: "lossy", quality_applied: 68 }))

      res = client.get_job_status("job_1")
      expect(res.mode_applied).to eq("lossy")
      expect(res.quality_applied).to eq(68)
    end

    it "leaves mode_applied and quality_applied nil for old jobs" do
      stub_request(:get, "#{base_url}/v1/optimize/status?job_id=job_old")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: JSON.generate({ job_id: "job_old", status: "completed" }))

      res = client.get_job_status("job_old")
      expect(res.mode_applied).to be_nil
      expect(res.quality_applied).to be_nil
    end
  end

  describe "#get_quota" do
    it "retrieves quota metrics" do
      stub_request(:get, "#{base_url}/v1/quota")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            plan:             "api_velocity",
            bytes_used:       2_500_000,
            quota_limit:      10_000_000,
            quota_percentage: 25.0
          })
        )

      quota = client.get_quota
      expect(quota.plan).to eq("api_velocity")
      expect(quota.bytes_used).to eq(2_500_000)
      expect(quota.quota_percentage).to eq(25.0)
    end
  end

  describe "#purge_cdn" do
    it "enqueues CDN cache invalidation" do
      stub_request(:post, "#{base_url}/v1/purge")
        .to_return(
          status: 202,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ message: "Purge accepted" })
        )

      res = client.purge_cdn(["https://cdn.smallpict.app/opt/photo.avif"])
      expect(res.message).to eq("Purge accepted")
    end
  end

  describe "#validate_key" do
    it "returns true on valid credentials and false on unauthorized" do
      stub_request(:get, "#{base_url}/v1/quota")
        .to_return(status: 200, body: JSON.generate({ plan: "free" }))

      expect(client.validate_key).to be true

      stub_request(:get, "#{base_url}/v1/quota")
        .to_return(status: 401, body: JSON.generate({ error: "Unauthorized" }))

      expect(client.validate_key).to be false
    end
  end
end
