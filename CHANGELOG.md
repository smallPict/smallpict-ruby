# Changelog

All notable changes to the `smallpict` gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `mode:` option on `optimize` (`"lossy"` default, `"extreme"`, `"lossless"`), with constants `SmallPict::Mode::LOSSY`, `EXTREME`, `LOSSLESS` and the frozen list `SmallPict::Mode::ALL`. The server checks the mode against the plan: `403 mode_not_in_plan` raises `PermissionDeniedError` with `details["mode"]` and `details["allowed_modes"]`; `400 invalid_mode` raises `ValidationError`.
- `JobStatusResult#mode_applied` and `#quality_applied`, as reported by the server (`nil` for jobs created before modes existed).
- `folder:` option on `optimize`, sent as `options.folder` and omitted when unset. The server stores the file under that folder of your account and lower-cases the value; `OptimizeResult#folder` and `JobStatusResult#folder` return it as stored (`nil` without one). The client rejects empty segments (`a//b`, leading or trailing `/`), `..` segments and more than 3 segments with `ValidationError` before any request; the server checks the full format (`400 invalid_folder` raises `ValidationError` with the server's message).
- `purge_cdn(purge_type: "folder", folder: "...")` purges one upload folder. `folder:` is required for that type (`ValidationError` before any request when missing or malformed) and is sent only with it; `url` and `all` purges are unchanged.

### Changed
- `429 purge_rate_limited` (hourly limit: 10 `folder` and 2 `all` purges per hour) raises `RateLimitError` without automatic retries, since the limit does not reset within seconds. Other 429 responses are still retried as before.

### Deprecated
- `lossless:` option on `optimize`. Use `mode: SmallPict::Mode::LOSSLESS` instead. `lossless: true` without `mode:` is sent as `mode: "lossless"`; `lossless: true` with a different `mode:` raises `ValidationError` before any request. Using it emits a `:deprecated` category warning (shown when `Warning[:deprecated]` is enabled). It will not be removed before the next major version.

### Fixed
- `lossless: true` used to be ignored by the server; it is now honoured (sent as `mode: "lossless"`). The SDK no longer sends `lossless` on the wire.

## [0.0.2] - 2026-08-22

### Added
- Official Ruby SDK implementation for SmallPict OpenAPI 3.1.0 API.
- Block-based global configuration (`SmallPict.configure { |c| ... }`) and standalone client instances (`SmallPict::Client.new`).
- Rails ActiveStorage Service adapter (`SmallPict::ActiveStorage::Service`).
- 4 unified core client methods: `optimize`, `get_quota`, `purge_cdn`, and `validate_key`.
- Helper `get_job_status` for polling asynchronous image conversion tasks.
- Faraday connection pooling with automatic retry and jitter on HTTP 429/5xx.
- Custom exception hierarchy with automatic secret redaction in `to_s` and `inspect`.
- Optional `:passthrough` fallback mode on quota limit exhaustion.
