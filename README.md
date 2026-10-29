# SmallPict Ruby SDK

Official Ruby gem for the [SmallPict Image Optimization API](https://smallpict.app) — high-performance next-gen image transcoding (AVIF, WebP), smart compression, Edge CDN delivery, cache purging, and Rails ActiveStorage support.

[![Gem Version](https://img.shields.io/gem/v/smallpict.svg)](https://rubygems.org/gems/smallpict)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D3.2-ruby.svg)](https://www.ruby-lang.org)

---

## ⚡ Features

- **💎 Idiomatic Ruby Design:** Block-based configuration (`SmallPict.configure`) and flexible standalone instances.
- **🚀 Rails ActiveStorage Ready:** Built-in service adapter (`SmallPict::ActiveStorage::Service`).
- **🛡️ Secure HMAC-SHA256 & Bearer Auth:** Tamper-proof payload verification.
- **✨ 4 Core Unified Methods:** `optimize()`, `get_quota()`, `purge_cdn()`, and `validate_key()`.
- **🔄 Resilience & Fault Tolerance:** Automatic `Idempotency-Key` UUID injection, 30s timeouts, and exponential backoff with jitter on HTTP 429/5xx.
- **🔒 Zero-Leak Privacy:** API keys and credentials are automatically redacted from `to_s` and `inspect` error logs.

---

## 📥 Installation

Add to your application's `Gemfile`:

```ruby
gem "smallpict", "~> 0.0.2"
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

```ruby
require "smallpict"

SmallPict.configure do |config|
  config.api_key    = ENV["SMALLPICT_API_KEY"]
  config.secret_key = ENV["SMALLPICT_SECRET_KEY"] # Optional HMAC Secret Key
end

image_data = File.binread("hero-banner.png")

result = SmallPict.optimize(
  image_data,
  format: "avif",
  quality: 80,
  max_width: 1920,
  mode: SmallPict::Mode::LOSSY # LOSSY (default) | EXTREME | LOSSLESS; replaces the deprecated `lossless:`
)

puts "Optimized CDN URL: #{result.url}"
puts "Saved: #{result.savings_percentage}% (#{result.bytes_saved} bytes)"
```

### 2. Rails Initializer (`config/initializers/smallpict.rb`)

```ruby
SmallPict.configure do |config|
  config.api_key       = Rails.application.credentials.dig(:smallpict, :api_key)
  config.secret_key    = Rails.application.credentials.dig(:smallpict, :secret_key)
  config.fallback_mode = :passthrough # :throw | :passthrough
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
```

---

## 🧪 Testing

```bash
bundle exec rspec
bundle exec rubocop
```

---

## 🔒 Security & Schema Compatibility (2026)

- **`mime_type` & `content_type` Dual Support**: `OptimizeOptions` accepts both `mime_type` and `content_type` keyword arguments. Outgoing optimization payloads include both `mime_type` and `content_type` fields, ensuring seamless zero-disruption compatibility across all SmallPict API versions.

---

## 📄 License

MIT © [SmallPict Engineering](https://smallpict.app)
