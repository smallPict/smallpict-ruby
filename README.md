# SmallPict Ruby SDK

Official Ruby gem for the [SmallPict Image Optimization API](https://smallpict.app) — high-performance next-gen image transcoding (AVIF, WebP), smart compression, Edge CDN delivery and cache purging.

[![Gem Version](https://img.shields.io/gem/v/smallpict.svg)](https://rubygems.org/gems/smallpict)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D3.2-ruby.svg)](https://www.ruby-lang.org)

---

## ⚡ Features

- **💎 Idiomatic Ruby Design:** Block-based configuration (`SmallPict.configure`) and flexible standalone instances.
- **🛡️ HMAC-SHA256 request signing:** every request is signed with your secret key; both `api_key` and `secret_key` are required.
- **✨ 4 Core Unified Methods:** `optimize()`, `get_quota()`, `purge_cdn()`, and `validate_key()`.
- **🔄 Resilience & Fault Tolerance:** Automatic `Idempotency-Key` UUID injection, 30s timeouts, and exponential backoff with jitter on HTTP 429/5xx.
- **🔒 Zero-Leak Privacy:** API keys and secrets are redacted from error messages, and `Client#inspect` / `Configuration#inspect` show only the base URL.

---

## 📥 Installation

Add to your application's `Gemfile`:

```ruby
gem "smallpict", "~> 0.1.0"
```

And then execute:

```bash
bundle install
# or install directly
gem install smallpict
```

---

## 🚀 Quick Start

### 1. Global Block Configuration & Standalone Ruby

`SmallPict.configure` is process-global: every `SmallPict.optimize` call in the process shares it. Code that serves several tenants with different keys builds its own `SmallPict::Client.new(api_key: ..., secret_key: ...)` per tenant.

```ruby
require "smallpict"

SmallPict.configure do |config|
  config.api_key    = ENV["SMALLPICT_API_KEY"]
  config.secret_key = ENV["SMALLPICT_SECRET_KEY"]
end

image_data = File.binread("hero-banner.png")
# A source can be the image bytes (String), an open File or IO, or a Pathname.

result = SmallPict.optimize(
  image_data,
  format: "avif",
  quality: 80,
  max_width: 1920,
  mode: SmallPict::Mode::LOSSY, # LOSSY (default) | EXTREME | LOSSLESS | AUTO; replaces the deprecated `lossless:`
  folder: "products/shoes"      # optional, 1-3 segments; stored lower case, returned as result.folder
)

puts "Optimized CDN URL: #{result.url}"
puts "Saved: #{result.savings_percentage}% (#{result.bytes_saved} bytes)"
```

#### What `optimize` does

`optimize` returns a finished job. It sends the request, uploads the bytes to the pre-signed `upload_url` the API returns, then polls the job status every `poll_interval` seconds (default 1) until the job is completed, for at most `wait_timeout` seconds (default 120). The result has `status == "completed"`, `url`, `format`, `bytes_saved`, `mode_applied`, `quality_applied` and `folder` from the job status, plus `original_size` (the bytes you sent), `compressed_size` and `savings_percentage`.

- Pass the image as bytes (a String), an IO (`File`, `Tempfile`, `StringIO`) or a local file path. An `http://` or `https://` URL raises `SmallPict::ValidationError`: the API does not fetch URLs, so download the image and pass its bytes.
- A failed job raises `SmallPict::Error` with `code == "job_failed"`, the server's message and `details["job_id"]`. A refused upload raises `SmallPict::Error` with `code == "upload_failed"` and the HTTP status in `status_code`.
- A job still running after `wait_timeout` raises `SmallPict::TimeoutError` with the job id in the message. The job keeps running on the server; read it later with `SmallPict.get_job_status(job_id)`.
- A retry after a 5xx may create a second job until the server honours `Idempotency-Key`.

```ruby
client = SmallPict::Client.new(api_key: ENV["SMALLPICT_API_KEY"], secret_key: ENV["SMALLPICT_SECRET_KEY"],
                               poll_interval: 2, wait_timeout: 60)
```

`AUTO` picks, per image, the lowest quality that keeps the visual score (SSIMULACRA 2) at or above 70, and ignores `quality`. It is on WP Pro and Business, Velocity, Momentum and sandbox keys (5 auto jobs per minute per sandbox key); where it cannot search (PNG or GIF output, animation, time limit) the job is lossy and `mode_applied` says so.

`EXTREME` gives the smallest files on every plan. Leave `quality` out so the server uses its default for the output format; a quality you set is kept or raised to the format floor. Mode comparison: https://smallpict.app/en/docs/image-settings

```ruby
result = SmallPict.optimize(
  File.binread("hero-banner.png"),
  format: "webp",
  mode: SmallPict::Mode::EXTREME # no quality: the server picks it per format
)
```

### 2. Rails Initializer (`config/initializers/smallpict.rb`)

```ruby
SmallPict.configure do |config|
  config.api_key       = Rails.application.credentials.dig(:smallpict, :api_key)
  config.secret_key    = Rails.application.credentials.dig(:smallpict, :secret_key)
  config.fallback_mode = :passthrough # :throw | :passthrough
  config.poll_interval = 1   # seconds between job status polls in optimize
  config.wait_timeout  = 120 # seconds optimize waits before SmallPict::TimeoutError
end
```

### 3. Rails Controller Example

```ruby
class MediaController < ApplicationController
  def create
    uploaded_file = params[:image]

    result = SmallPict.optimize(
      uploaded_file.tempfile,
      format: "auto",
      quality: 85
    )

    render json: {
      url: result.url,
      format: result.format,
      savings: "#{result.savings_percentage}%"
    }
  end
end
```

---

## 📊 Account Quota & Edge CDN Purge

```ruby
# 1. Check real-time quota usage
quota = SmallPict.get_quota
puts "Plan: #{quota.plan}, Quota Used: #{quota.quota_percentage}%"

# 2. Invalidate CDN cache for updated images
purge = SmallPict.purge_cdn(["https://cdn.smallpict.app/opt/hero-banner.avif"])
puts purge.message

# 3. Purge one upload folder, or all of your files
SmallPict.purge_cdn(purge_type: "folder", folder: "products/shoes")
SmallPict.purge_cdn(purge_type: "all")
# Folder purges are limited to 10 per hour and "all" to 2 per hour: one more raises
# SmallPict::RateLimitError (429 purge_rate_limited), which the client does not retry.
```

### Capacity and upgrade links

`get_quota` also returns the read-only `capacity` of the key's product. Members that do not apply to your plan are `nil`, and `capacity` itself is `nil` when the server could not read it or does not send it.

```ruby
cap = SmallPict.get_quota.capacity
if cap
  puts "Storage: #{cap.storage.used_bytes}/#{cap.storage.limit_bytes}" if cap.storage
  puts "CDN status: #{cap.cdn.status}" if cap.cdn
  puts "Account lapsed (#{cap.lapse.stage}), manage it at #{cap.manage_url}" if cap.lapse
end

begin
  SmallPict.optimize("photo.jpg")
rescue SmallPict::QuotaExceededError => e
  puts "Add capacity at #{e.upgrade_url}" if e.upgrade_url
rescue SmallPict::PermissionDeniedError => e
  puts "Allowed modes: #{e.allowed_modes.join(', ')}" if e.allowed_modes
end
```

Capacity is bought only in the dashboard. `manage_url` and `upgrade_url` are plain strings to show your users; the SDK never opens or fetches them.

---

## 🧪 Testing

```bash
bundle exec rspec
bundle exec rubocop
```

---

## 🔒 Security & Schema Compatibility (2026)

- **`content_type` alias**: `OptimizeOptions` still accepts `content_type:` as an alias of `mime_type:` for older callers; only `mime_type` is sent, which is the field the API reads.

---

## 📄 License

MIT © [SmallPict Engineering](https://smallpict.app)
