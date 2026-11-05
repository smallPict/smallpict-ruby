# frozen_string_literal: true

require "spec_helper"

# SDK_SPEC.md section 3d: optimize queues the job, PUTs the bytes, then polls the status.
RSpec.describe SmallPict::Client, "#optimize upload and wait" do
  let(:api_key) { "sp_sdk_test_1234567890" }
  let(:secret_key) { "sec_test_secret_123" }
  let(:base_url) { "https://api.smallpict.app" }
  let(:upload_url) { "https://staging.s3.amazonaws.com/in/job_w.jpg?X-Amz-Signature=abc" }
  let(:status_url) { "#{base_url}/v1/optimize/status?job_id=job_w" }
  let(:bytes) { "\xFF\xD8\xFFfake-jpeg-bytes".b }
  let(:client) do
    described_class.new(api_key: api_key, secret_key: secret_key, base_url: base_url,
                        poll_interval: 0.001, wait_timeout: 0.05)
  end

  def json(body, status: 200)
    { status: status, headers: { "Content-Type" => "application/json" }, body: JSON.generate(body) }
  end

  before do
    stub_request(:post, "#{base_url}/v1/optimize")
      .to_return(json({ job_id: "job_w", status: "queued", upload_url: upload_url,
                        object_key: "in/job_w.jpg", bucket: "staging" }, status: 202))
  end

  it "PUTs the exact bytes with only Content-Type and Content-Length, polls, and returns the status fields" do
    stub_request(:put, upload_url).to_return(status: 200)
    stub_request(:get, status_url)
      .to_return(json({ job_id: "job_w", status: "processing" }))
      .then.to_return(json({ job_id: "job_w", status: "completed", url: "https://cdn.smallpict.app/opt/a.webp",
                             format: "webp", bytes_saved: 6, mode_applied: "lossy", quality_applied: 80 }))

    result = client.optimize(bytes, filename: "a.jpg", mime_type: "image/jpeg", format: "webp")

    expect(WebMock).to(have_requested(:put, upload_url).with do |req|
      req.body.b == bytes &&
        req.headers["Content-Type"] == "image/jpeg" &&
        req.headers["Content-Length"] == bytes.bytesize.to_s &&
        (req.headers.keys.map(&:downcase) &
          %w[x-api-key x-timestamp x-signature authorization idempotency-key]).empty?
    end)
    expect(WebMock).to have_requested(:get, status_url).twice
    expect(result.job_id).to eq("job_w")
    expect(result.status).to eq("completed")
    expect(result.url).to eq("https://cdn.smallpict.app/opt/a.webp")
    expect(result.format).to eq("webp")
    expect(result.bytes_saved).to eq(6)
    expect(result.original_size).to eq(bytes.bytesize)
    expect(result.compressed_size).to eq(bytes.bytesize - 6)
    expect(result.savings_percentage).to eq((6.0 / bytes.bytesize * 100).round(2))
    expect(result.mode_applied).to eq("lossy")
    expect(result.quality_applied).to eq(80)
    expect(result.folder).to be_nil
    expect(result).not_to respond_to(:upload_url)
  end

  it "raises job_failed with the server message when the job fails" do
    stub_request(:put, upload_url).to_return(status: 200)
    stub_request(:get, status_url)
      .to_return(json({ job_id: "job_w", status: "failed",
                        error: { code: "upload_missing", message: "client upload never arrived" } }))

    expect { client.optimize(bytes) }.to raise_error(SmallPict::Error) { |e|
      expect(e.class).to eq(SmallPict::Error)
      expect(e.code).to eq("job_failed")
      expect(e.message).to include("client upload never arrived")
      expect(e.details).to eq({ "job_id" => "job_w" })
    }
  end

  it "raises TimeoutError naming the job when it does not finish in wait_timeout" do
    stub_request(:put, upload_url).to_return(status: 200)
    stub_request(:get, status_url).to_return(json({ job_id: "job_w", status: "processing" }))

    expect { client.optimize(bytes) }.to raise_error(SmallPict::TimeoutError) { |e|
      expect(e.message).to include("job_w")
      expect(e.message).to include("get_job_status")
    }
  end

  it "raises upload_failed with the HTTP status when storage refuses the PUT" do
    stub_request(:put, upload_url).to_return(status: 403, body: "<Error>SignatureDoesNotMatch</Error>")

    expect { client.optimize(bytes) }.to raise_error(SmallPict::Error) { |e|
      expect(e.class).to eq(SmallPict::Error)
      expect(e.code).to eq("upload_failed")
      expect(e.status_code).to eq(403)
      expect(e.message).to include("SignatureDoesNotMatch")
    }
    expect(WebMock).to have_requested(:put, upload_url).once
    expect(WebMock).not_to have_requested(:get, status_url)
  end

  it "raises NetworkError when the PUT cannot connect" do
    stub_request(:put, upload_url).to_raise(Faraday::ConnectionFailed.new("connection refused"))

    expect { client.optimize(bytes) }.to raise_error(SmallPict::NetworkError)
    expect(WebMock).to have_requested(:put, upload_url).once
  end

  %w[http://example.com/a.jpg https://example.com/a.jpg].each do |url|
    it "rejects the URL source #{url} with ValidationError before any request" do
      expect { client.optimize(url) }.to raise_error(SmallPict::ValidationError, /does not fetch URLs/)
      expect(WebMock).not_to have_requested(:post, "#{base_url}/v1/optimize")
    end
  end

  it "rejects a source that holds no bytes with ValidationError before any request" do
    expect { client.optimize(12_345) }.to raise_error(SmallPict::ValidationError)
    expect(WebMock).not_to have_requested(:post, "#{base_url}/v1/optimize")
  end

  it "defaults poll_interval to 1 s and wait_timeout to 120 s" do
    c = described_class.new(api_key: api_key)
    expect(c.poll_interval).to eq(1)
    expect(c.wait_timeout).to eq(120)
  end
end
