# Changelog

All notable changes to **mob_notify** are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed

- **Manifest `mob_version` matches the actual mob dep** (MOB-81). The
  plugin's `priv/mob_plugin.exs` pinned `mob_version: "~> 0.6"` while
  `mix.exs` pulled `{:mob, "~> 0.7"}`. Once a consumer ran
  `Manifest.validate/1`, the version-gate check would refuse the plugin
  outright — the plugin as shipped worked in host builds because that
  gate isn't invoked on every load. Bumped to `"~> 0.7"` to match the
  runtime dep.

---

## [0.1.1] - 2026-06-16

### Changed
- Signed release: the published package now carries a verified Ed25519
  signature (shared mob first-party key, regenerated in CI on every
  release). Generated apps trust it via `config :mob, :trusted_plugins`,
  so it clears the plugin signature gate without `acknowledge_unsafe_plugins`.

## [0.1.0] - 2026-06-12

Initial release. Local and push notifications for Mob apps — the device half, pairs with the server-side `mob_push` package.

- `MobNotify.schedule/2`, `cancel/2`, and `register_push/1`; delivery rides mob core.
- Extracted from mob core in the 0.7.0 plugin-extraction wave.
- Requires `mob ~> 0.7`.
