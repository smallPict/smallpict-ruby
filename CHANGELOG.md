# Changelog

All notable changes to the `smallpict` gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Rails ActiveStorage Service adapter (`SmallPict::ActiveStorage::Service`).
- 4 unified core client methods: `optimize`, `get_quota`, `purge_cdn`, and `validate_key`.
- Helper `get_job_status` for polling asynchronous image conversion tasks.
- Faraday connection pooling with automatic retry and jitter on HTTP 429/5xx.
- Custom exception hierarchy with automatic secret redaction in `to_s` and `inspect`.
- Optional `:passthrough` fallback mode on quota limit exhaustion.
