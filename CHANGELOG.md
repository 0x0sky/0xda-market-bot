# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-19

### Added

- Passwordless Telegram authentication with contextual `/status` responses and
  role-specific command scopes.
- Database-driven `/buy` catalog and admin-only user, server, role and pricing
  commands backed by the market API.
- `/apply_prices` and `/apply_price` workflows plus a daylight-saving-aware
  daily price digest for active admins.
- Retry and cold-start handling for temporary market API failures.
- Separate Render test and production web services and a production digest
  cron service.

### Changed

- **Breaking:** replaced the `premium_9m` product callback/SKU with
  `premium_12m` to match the core catalog.
- Product and price-form rows now come entirely from the database-backed core
  catalog instead of a duplicated bot template.
- Added `uk_UA` interface and product localization with `en_US` as the default
  fallback.
- Price application forms now show short names, timestamps and internal editor
  UUIDs supplied by the core.

### Fixed

- Kept Telegram webhook handling responsive while the market core wakes up and
  retried transient upstream and non-JSON failures.
- Aligned production/test branch mapping and production environment URLs.

### Security

- Verified Telegram webhook secrets, hid privileged commands from non-admins
  and retained core-side authorization for every admin operation.

[Unreleased]: https://github.com/0x0sky/0xda-market-bot/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/0x0sky/0xda-market-bot/releases/tag/v0.1.0
