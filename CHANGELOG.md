# Changelog

All notable changes to the `smallpict` gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.8] - Unreleased

Next release after v0.0.7. It includes the changes first written up as 0.1.0, which was never tagged or published.

### Fixed
- A `base_url` that ends in `/v1` (the form `SDK_SPEC.md` names) no longer produces `/v1/v1/...` paths and 404s; the client strips the suffix and adds `/v1` itself.
- A queued optimize answer without `upload_url` or `job_id` raises `SmallPict::Error` with code `invalid_response` before any upload, instead of a raw URI error from Faraday.
- Every Faraday error (for example `Faraday::SSLError` from a proxy with its own CA) is wrapped in `SmallPict::NetworkError`, so `rescue SmallPict::Error` catches it. `validate_key` returns `false` only for 401 and 403; an outage raises `NetworkError` instead of being reported as an invalid key.
- `SmallPict.configure` takes effect after the first module-level call too. The memoised default client was never rebuilt, so a second `configure` (per-tenant rake task, test suite) kept the first keys.
- The signature covers the request path without the query string, as the contract says; the status poll used to sign `/v1/optimize/status?job_id=...`, which only worked through a server-side fallback. `get_job_status` URL-encodes the job id instead of interpolating it raw into the query.
- A 2xx response whose body is not JSON (a proxy or WAF page) raises `SmallPict::Error` with code `invalid_response` instead of being read as an empty result: `get_quota` returned plan `"free"`, `validate_key` returned `true` and `optimize` polled a phantom job until `wait_timeout`.
- `mime_type` is detected when the caller gives none: from the first bytes (PNG, JPEG, GIF, WebP, AVIF), then from the filename extension, then `image/jpeg`. A PNG passed as bytes or a Tempfile was declared and uploaded as `image/jpeg`. An explicit `mime_type:` still wins.
- `Retry-After` is capped at 30 seconds (`Client::MAX_RETRY_AFTER`). A 429 or 5xx with `Retry-After: 60` slept a Puma thread for a minute per attempt, up to three times in one request; the retry now waits at most 30 s.
- Every request carries a fresh `X-Nonce`, so a retry inside the same second is no longer refused by the server as a replay (401 "Replay attack detected"); before, a transient 429 or 5xx could surface as `AuthenticationError`. `Idempotency-Key` is generated once per call and kept across retries instead of once per attempt.
- `SmallPict::Client#inspect` and `SmallPict::Configuration#inspect` (and `to_s`) no longer print the API key and secret key; they show the base URL only. `Error.sanitize` also masks server-issued `sps_...` secrets, not only the `sec_`/`secret_` fixtures.
- `optimize(bytes)` no longer raises `ArgumentError: path name contains null byte` for real image data. A String source was probed with `File.exist?`, which refuses the NUL bytes every PNG and JPEG header contains, so `SmallPict.optimize(File.binread("x.png"))` crashed before any request. A String is now sent as bytes unless it is NUL-free and names an existing file; a `Pathname` is read from disk and its basename becomes `filename`.

### Removed
- The `fit:` option (always sent as `"cover"`, not a server field, so it never did anything) and the `content_type` field of the request body (a duplicate of `mime_type`). `content_type:` is still accepted as an alias of `mime_type:`. The `faraday-retry` runtime dependency, which was never required (retries are implemented in the client), is gone from the gemspec.
- `SmallPict::ActiveStorage::Service`. It was not an `ActiveStorage::Service` (no `upload`, `download`, `delete`, `exist?`, `url`; not configurable from `config/storage.yml`), and its `url_for` sent an empty body that the API rejects with 400, so it always raised. Use `SmallPict.optimize` on the bytes you hold.

### Changed
- RuboCop passes and runs in CI. `.rubocop.yml` now states the code's own conventions (double quotes, table-aligned hashes, 140-column lines outside specs) and turns off the size metrics and two naming cops that argued with the public API; the remaining offences were autocorrected.
- **`secret_key` is required.** `SmallPict::Client.new` raises `ValidationError` when neither `secret_key:`, `SmallPict.configure` nor `SMALLPICT_SECRET_KEY` provides one. The Bearer-only mode (API key without signature) is gone: the API refuses it with 403 "Legacy Bearer token format is no longer supported", so a client built that way never worked. README examples pass both keys.
- Release workflow runs `bundle exec rspec` before `gem build`, passes the RubyGems key through `GEM_HOST_API_KEY` instead of writing `~/.gem/credentials`, restricts the token to `contents: read`, and pins actions to commit SHAs.

### Fixed
- **`optimize` now returns an optimized image.** `POST /v1/optimize` only queues the job and returns a pre-signed `upload_url`; the SDK stopped there, so the worker failed every job with "client upload never arrived" and callers got an empty `url` with 0 % saved. `optimize` now PUTs the bytes to `upload_url` (plain PUT with `Content-Type` and `Content-Length` as sent, no API headers, no retry), polls `GET /v1/optimize/status` every `poll_interval` (default 1 s) and returns once the job is `completed`, with `url`, `format`, `bytes_saved`, `mode_applied`, `quality_applied` and `folder` from the job status (`SDK_SPEC.md` section 3d).

### Added
- `poll_interval` (seconds, default 1) and `wait_timeout` (seconds, default 120) on `SmallPict::Client.new` and `SmallPict.configure`.
- `OptimizeResult#mode_applied` and `#quality_applied`.
- Error codes `job_failed` (a failed job: `SmallPict::Error` with the server's `error.message` and `details["job_id"]`) and `upload_failed` (the storage refused the PUT: `SmallPict::Error` with the HTTP status in `#status_code`). A job still running after `wait_timeout` raises `SmallPict::TimeoutError` with the job id; it keeps running on the server, and `get_job_status` reads it later. A PUT that cannot connect raises `NetworkError`.

### Changed
- **`OptimizeResult#status` is always `"completed"`** and `#upload_url` is gone: there is no result to return before the job finished. Code that checked for `"queued"` or used `upload_url` to upload by itself can drop that.
- **An `http://` or `https://` string source raises `ValidationError`** before any request. The API never fetched URLs, so such calls failed on the server; the SDK does not download on your behalf. A source that is neither an IO, a file path nor a String of bytes raises `ValidationError` too (it used to send `filesize: 0`).
- `compressed_size` and `savings_percentage` are derived from the bytes sent and `bytes_saved` of the job status.
- README: "What `optimize` does".

## [0.0.7] - 2026-10-31

### Added
- `SmallPict::Mode::AUTO` (`"auto"`, also in `Mode::ALL`): the server picks the quality per image from a visual score (CMP-07). Plans: WP Pro and Business, Velocity, Momentum and sandbox; a server without auto enabled answers `400 invalid_mode` (`ValidationError`).
- `mode:` option on `optimize` (`"lossy"` default, `"extreme"`, `"lossless"`), with constants `SmallPict::Mode::LOSSY`, `EXTREME`, `LOSSLESS` and the frozen list `SmallPict::Mode::ALL`. The server checks the mode against the plan: `403 mode_not_in_plan` raises `PermissionDeniedError` with `details["mode"]` and `details["allowed_modes"]`; `400 invalid_mode` raises `ValidationError`.
- `JobStatusResult#mode_applied` and `#quality_applied`, as reported by the server (`nil` for jobs created before modes existed).
- `folder:` option on `optimize`, sent as `options.folder` and omitted when unset. The server stores the file under that folder of your account and lower-cases the value; `OptimizeResult#folder` and `JobStatusResult#folder` return it as stored (`nil` without one). The client rejects empty segments (`a//b`, leading or trailing `/`), `..` segments and more than 3 segments with `ValidationError` before any request; the server checks the full format (`400 invalid_folder` raises `ValidationError` with the server's message).
- `purge_cdn(purge_type: "folder", folder: "...")` purges one upload folder. `folder:` is required for that type (`ValidationError` before any request when missing or malformed) and is sent only with it; `url` and `all` purges are unchanged.
- `QuotaResponse#capacity`: the read-only capacity of `GET /v1/quota` as `SmallPict::Models::Capacity` (`period_end`, `storage`, `cdn`, `booster` with `next_expiry`, `lapse`, `manage_url`). Members that do not apply to the plan are `nil`; `capacity` is `nil` when the server could not read it and on older servers that do not send it. Existing quota fields are unchanged. Capacity is bought only in the dashboard; the SDK exposes `manage_url` as a string and never opens or fetches it.
- `SmallPict::Error#upgrade_url` on every error: `details["upgrade_url"]` when it is a string (sent with `402` quota, storage and read-only errors), otherwise `nil`. `PermissionDeniedError#allowed_modes` returns `details["allowed_modes"]` of `403 mode_not_in_plan`, otherwise `nil`. Status-to-class mapping is unchanged.

### Changed
- README: example of `mode: SmallPict::Mode::EXTREME` without `quality:`.
- `429 purge_rate_limited` (hourly limit: 10 `folder` and 2 `all` purges per hour) raises `RateLimitError` without automatic retries, since the limit does not reset within seconds. Other 429 responses are still retried as before.
- Errors raised as the base `SmallPict::Error` (statuses without a dedicated class, such as `409`) now carry the server's `error.code` in `#code` instead of `"INTERNAL_ERROR"`; `"INTERNAL_ERROR"` remains when the body has no code. Typed errors keep their fixed codes.

### Deprecated
- `lossless:` option on `optimize`. Use `mode: SmallPict::Mode::LOSSLESS` instead. `lossless: true` without `mode:` is sent as `mode: "lossless"`; `lossless: true` with a different `mode:` raises `ValidationError` before any request. Using it emits a `:deprecated` category warning (shown when `Warning[:deprecated]` is enabled). It will not be removed before the next major version.

### Fixed
- `quality:` is no longer sent when unset (its default is now `nil` instead of `80`), so the server picks the default per mode: lossy stays at 80, and `extreme` now gets its per-codec default instead of a lossy-sized Q80 result. A quality you set is still sent. `OptimizeOptions#quality` returns `nil` when unset.
- `lossless: true` used to be ignored by the server; it is now honoured (sent as `mode: "lossless"`). The SDK no longer sends `lossless` on the wire.

## [0.0.2] - 2026-08-22

### Added
- Official Ruby SDK implementation for SmallPict OpenAPI 3.1.0 API.
- Block-based global configuration (`SmallPict.configure { |c| ... }`) and standalone client instances (`SmallPict::Client.new`).
- Rails ActiveStorage Service adapter (`SmallPict::ActiveStorage::Service`). Removed in the next release: it was not an ActiveStorage service.
- 4 unified core client methods: `optimize`, `get_quota`, `purge_cdn`, and `validate_key`.
- Helper `get_job_status` for polling asynchronous image conversion tasks.
- Faraday connection pooling with automatic retry and jitter on HTTP 429/5xx.
- Custom exception hierarchy with automatic secret redaction in `to_s` and `inspect`.
- Optional `:passthrough` fallback mode on quota limit exhaustion.
