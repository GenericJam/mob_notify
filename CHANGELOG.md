# Changelog

All notable changes to **mob_notify** are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2026-06-12

Initial release. Local and push notifications for Mob apps — the device half, pairs with the server-side `mob_push` package.

- `MobNotify.schedule/2`, `cancel/2`, and `register_push/1`; delivery rides mob core.
- Extracted from mob core in the 0.7.0 plugin-extraction wave.
- Requires `mob ~> 0.7`.
