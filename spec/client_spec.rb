# frozen_string_literal: true

require "spec_helper"

RSpec.describe SmallPict::Client do
  let(:api_key) { "sp_sdk_test_1234567890" }
  let(:secret_key) { "sec_test_secret_123" }
  let(:base_url) { "https://api.smallpict.app" }
  let(:client) { described_class.new(api_key: api_key, secret_key: secret_key, base_url: base_url, poll_interval: 0.001) }
  let(:upload_url) { "https://staging.s3.amazonaws.com/in/upload?X-Amz-Signature=abc" }

  # optimize queues the job, PUTs the bytes to upload_url, then polls the status (SDK_SPEC.md 3d).
  def queued_body(job_id)
    JSON.generate({ job_id: job_id, status: "queued", upload_url: upload_url, object_key: "in/upload", bucket: "staging" })
  end

  def stub_upload_and_status(job_id, status_fields = {})
    stub_request(:put, upload_url).to_return(status: 200)
    stub_request(:get, "#{base_url}/v1/optimize/status?job_id=#{job_id}")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: JSON.generate({ job_id: job_id, status: "completed", url: "https://cdn.smallpict.app/opt/x.webp",
                                       format: "webp", bytes_saved: 0 }.merge(status_fields)))
  end

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
        .to_return(status: 202, headers: { "Content-Type" => "application/json" }, body: queued_body("job_rb_123"))
      stub_upload_and_status("job_rb_123", url: "https://cdn.smallpict.app/opt/photo.avif", format: "avif", bytes_saved: 12)

      result = client.optimize("fake image data", format: "avif", quality: 85)

      expect(result.job_id).to eq("job_rb_123")
      expect(result.status).to eq("completed")
      expect(result.url).to eq("https://cdn.smallpict.app/opt/photo.avif")
      expect(result.format).to eq("avif")
      expect(result.original_size).to eq(15)
      expect(result.compressed_size).to eq(3)
      expect(result.savings_percentage).to eq(80.0)
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
        secret_key:    secret_key,
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
      before do
        stub_request(:post, "#{base_url}/v1/optimize")
          .to_return(status: 202, headers: { "Content-Type" => "application/json" }, body: queued_body("job_mode"))
        stub_upload_and_status("job_mode")
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
        ["mode auto",              { mode: "auto" },                    "auto"],
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
        expect(SmallPict::Mode::ALL).to eq(%w[lossy extreme lossless auto])
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

    context "folder" do
      before do
        stub_request(:post, "#{base_url}/v1/optimize")
          .to_return(status: 202, headers: { "Content-Type" => "application/json" }, body: queued_body("job_f"))
        stub_upload_and_status("job_f", folder: "products/shoes")
      end

      def sent_options
        options = nil
        expect(WebMock).to(have_requested(:post, "#{base_url}/v1/optimize").with do |req|
          options = JSON.parse(req.body)["options"]
        end)
        options
      end

      it "sends folder as options.folder and surfaces it from the job status" do
        result = client.optimize("img", folder: "Products/Shoes")
        expect(sent_options["folder"]).to eq("Products/Shoes")
        expect(result.folder).to eq("products/shoes")
      end

      it "omits folder when unset" do
        client.optimize("img")
        expect(sent_options).not_to have_key("folder")
      end

      %w[a//b /a a/ ../x a/../b a/b/c/d].each do |bad|
        it "rejects #{bad.inspect} without an HTTP call" do
          expect { client.optimize("img", folder: bad) }.to raise_error(SmallPict::ValidationError)
          expect(WebMock).not_to have_requested(:post, "#{base_url}/v1/optimize")
        end
      end
    end

    context "quality" do
      before do
        stub_request(:post, "#{base_url}/v1/optimize")
          .to_return(status: 202, headers: { "Content-Type" => "application/json" }, body: queued_body("job_q"))
        stub_upload_and_status("job_q")
      end

      def sent_options
        options = nil
        expect(WebMock).to(have_requested(:post, "#{base_url}/v1/optimize").with do |req|
          options = JSON.parse(req.body)["options"]
        end)
        options
      end

      it "omits quality when unset so the server picks the default per mode" do
        client.optimize("img", mode: SmallPict::Mode::EXTREME)
        expect(sent_options).not_to have_key("quality")
      end

      it "sends quality when set" do
        client.optimize("img", mode: SmallPict::Mode::EXTREME, quality: 70)
        expect(sent_options["quality"]).to eq(70)
      end
    end

    it "raises ValidationError with the server message on 400 invalid_folder" do
      stub_request(:post, "#{base_url}/v1/optimize")
        .to_return(status: 400, headers: { "Content-Type" => "application/json" },
                   body: JSON.generate({ error: { code: "invalid_folder", message: "folder has an invalid character" } }))

      expect { client.optimize("img", folder: "bad.name") }.to raise_error(SmallPict::ValidationError) { |e|
        expect(e.message).to include("folder has an invalid character")
      }
    end
  end

  describe "#get_job_status" do
    it "exposes folder as returned" do
      stub_request(:get, "#{base_url}/v1/optimize/status?job_id=job_f")
        .to_return(status: 200, body: JSON.generate({ job_id: "job_f", status: "completed", folder: "blog/2026" }))

      expect(client.get_job_status("job_f").folder).to eq("blog/2026")
    end

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

    def sent_purge_body
      body = nil
      expect(WebMock).to(have_requested(:post, "#{base_url}/v1/purge").with { |req| body = JSON.parse(req.body) })
      body
    end

    it "keeps the url purge body unchanged, without folder" do
      stub_request(:post, "#{base_url}/v1/purge").to_return(status: 202, body: "{}")
      client.purge_cdn(["https://cdn.smallpict.app/a.avif"], folder: "ignored")
      expect(sent_purge_body).to eq("purge_type" => "url", "urls" => ["https://cdn.smallpict.app/a.avif"])
    end

    it "sends folder with purge_type folder" do
      stub_request(:post, "#{base_url}/v1/purge").to_return(status: 202, body: "{}")
      client.purge_cdn(purge_type: "folder", folder: "products/shoes")
      expect(sent_purge_body).to eq("purge_type" => "folder", "urls" => [], "folder" => "products/shoes")
    end

    it "requires folder for purge_type folder, without an HTTP call" do
      expect { client.purge_cdn(purge_type: "folder") }.to raise_error(SmallPict::ValidationError)
      expect { client.purge_cdn(purge_type: "folder", folder: "a/../b") }.to raise_error(SmallPict::ValidationError)
      expect(WebMock).not_to have_requested(:post, "#{base_url}/v1/purge")
    end

    it "raises RateLimitError on 429 purge_rate_limited and does not retry" do
      stub_request(:post, "#{base_url}/v1/purge")
        .to_return(status: 429, headers: { "Retry-After" => "1800" },
                   body: JSON.generate({ error: { code: "purge_rate_limited", message: "Too many folder purges" } }))
      allow(client).to receive(:sleep)

      expect { client.purge_cdn(purge_type: "folder", folder: "blog") }.to raise_error(SmallPict::RateLimitError) { |e|
        expect(e.message).to include("Too many folder purges")
      }
      expect(WebMock).to have_requested(:post, "#{base_url}/v1/purge").once
      expect(client).not_to have_received(:sleep)
    end

    it "still retries other 429s" do
      stub_request(:post, "#{base_url}/v1/purge")
        .to_return({ status: 429, body: JSON.generate({ error: { code: "RATE_LIMIT_EXCEEDED", message: "slow down" } }) },
                   { status: 202, body: "{}" })
      allow(client).to receive(:sleep)

      client.purge_cdn(purge_type: "all")
      expect(WebMock).to have_requested(:post, "#{base_url}/v1/purge").twice
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

RSpec.describe SmallPict::Client, "source handling" do
  let(:base_url) { "https://api.smallpict.app" }
  let(:client) { described_class.new(api_key: "sp_sdk_test_1234567890", secret_key: "sec_test_secret_123", base_url: base_url, poll_interval: 0.001) }
  let(:upload_url) { "https://staging.s3.amazonaws.com/in/upload?X-Amz-Signature=abc" }
  let(:png_bytes) { "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR".b }

  def stub_flow
    posts = []
    stub_request(:post, "#{base_url}/v1/optimize").with { |req| posts << JSON.parse(req.body) }
      .to_return(status: 202, headers: { "Content-Type" => "application/json" },
                 body: JSON.generate({ job_id: "j1", status: "queued", upload_url: upload_url, object_key: "k", bucket: "b" }))
    stub_request(:put, upload_url).to_return(status: 200)
    stub_request(:get, "#{base_url}/v1/optimize/status?job_id=j1")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: JSON.generate({ job_id: "j1", status: "completed", url: "https://cdn/x.avif", format: "avif", bytes_saved: 1 }))
    posts
  end

  it "sends a String with a PNG header as raw bytes" do
    posts = stub_flow
    client.optimize(png_bytes, mime_type: "image/png")
    expect(posts.first["filesize"]).to eq(png_bytes.bytesize)
  end

  it "reads a Pathname source from disk" do
    posts = stub_flow
    file = Tempfile.new(["img", ".png"], binmode: true)
    file.write(png_bytes)
    file.close
    client.optimize(Pathname.new(file.path))
    expect(posts.first["filesize"]).to eq(png_bytes.bytesize)
    expect(posts.first["filename"]).to eq(File.basename(file.path))
  end

  it "sends a String that is not an existing file as bytes" do
    posts = stub_flow
    client.optimize("photo.jpg")
    expect(posts.first["filesize"]).to eq(9)
  end
end

RSpec.describe SmallPict::Client, "retry headers" do
  let(:base_url) { "https://api.smallpict.app" }
  let(:client) { described_class.new(api_key: "sp_sdk_test_1234567890", secret_key: "sec_test_secret_123", base_url: base_url, max_retries: 1) }

  it "sends a new X-Nonce and the same Idempotency-Key on a retry" do
    seen = []
    stub_request(:post, "#{base_url}/v1/purge").with { |req| seen << req.headers }
      .to_return({ status: 503, body: JSON.generate({ error: { code: "INTERNAL_ERROR", message: "try again" } }) },
                 { status: 202, body: JSON.generate({ message: "Purge accepted" }) })
    allow(client).to receive(:sleep)

    client.purge_cdn(purge_type: "all")

    expect(seen.length).to eq(2)
    nonces = seen.map { |h| h["X-Nonce"] }
    expect(nonces).to all(be_a(String))
    expect(nonces.uniq.length).to eq(2)
    expect(seen[0]["Idempotency-Key"]).to eq(seen[1]["Idempotency-Key"])
  end
end

RSpec.describe SmallPict::Client, "secret key" do
  it "raises ValidationError when secret_key is missing" do
    SmallPict.configuration.secret_key = nil
    expect { described_class.new(api_key: "sp_sdk_test_1234567890") }
      .to raise_error(SmallPict::ValidationError, /secret key/)
  end
end
