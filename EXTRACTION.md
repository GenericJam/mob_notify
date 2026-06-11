# mob_notify extraction — survey + staged plan

Wave-2 extraction of `Mob.Notify` from mob core. Staged like mob_camera
(Stage 1a = Elixir layer; native + strips follow), because the survey found
notify is MORE entangled with core/host than camera was.

## Survey (2026-06-11) — where everything lives today

| Piece | Location | Moves? |
|---|---|---|
| `Mob.Notify` Elixir API (schedule/cancel/register_push) | mob `lib/mob/notify.ex` | → plugin (`MobNotify`) |
| NIF stubs `notify_schedule/1, notify_cancel/1, notify_register_push/0` | mob `src/mob_nif.erl` | → plugin `src/mob_notify_nif.erl` |
| iOS scheduling/cancel/register (`nif_notify_*`) | mob `ios/mob_nif.m:3238-3319` | → plugin `priv/native/ios/mob_notify_nif.m` (Stage 1b) |
| iOS `MobNotificationDelegate` + `g_notif_delegate` (delivery: foreground present + tap) | mob `ios/mob_nif.m:3175-3236, 2125-2128` | **STAYS IN CORE** |
| iOS `mob_send_push_token` (called by HOST AppDelegate) | mob `ios/mob_nif.m:2132-2145`, exported in `mob_beam.h`, caller in mob_new `ios/AppDelegate.m.eex` | **STAYS IN CORE** (host→core symbol; moving it = cross-library link problem, cf. `g_preview_session`) |
| iOS launch-notification handoff (`mob_set_launch_notification_json` + `nif_take_launch_notification`) | mob `ios/mob_nif.m:2120-2170` | **STAYS IN CORE** — consumed by core `Mob.Screen` (`lib/mob/screen.ex:218`) |
| Android `nif_notify_*` zig + Bridge method caches | mob `android/jni/mob_nif.zig:2727-2771, 3426-3428, 266-268` | → plugin `priv/native/jni/mob_notify_nif.zig` (Stage 1b) |
| Android Kotlin `notify_schedule/cancel/register_push` | mob_new `MobBridge.kt.eex` (~1450-1520) | → plugin `priv/native/android/MobNotifyBridge.kt` (Stage 1b) |
| Android `MobFirebaseService` (FCM token refresh + incoming push) | mob_new template, HOST package (`.MobFirebaseService` + manifest `<service>`) | **STAYS IN HOST TEMPLATE** — FirebaseMessagingService subclass must be a host class; declared via this plugin's `host_requirements` |
| Android launch-notification (`MobBridge.setLaunchNotification` → `mob_set_launch_notification`) | mob_new template + mob `android/jni/mob_nif.zig:2086` | **STAYS IN CORE/HOST** |
| `{:notification, payload}` delivery → `Mob.Screen` → `Mob.Plugins.dispatch_notification` | mob core | **STAYS IN CORE** (shared with the tier-4 plugin dispatcher) |

## The descope line (mirrors camera's preview-stays-in-core)

**Plugin owns:** the user-facing API — scheduling, cancellation, push
REGISTRATION. **Core keeps:** all DELIVERY plumbing (notification-center
delegate, push-token forwarding from the host AppDelegate, launch-notification
handoff, the `{:notification, ...}` message path the tier-4 dispatcher rides).

Rationale: delivery is wired into host-app shells (AppDelegate symbols, a
host-package Android service) and core screens; moving it needs either weak
externs in every host shell or a plugin-symbol registry — net-new capability,
not worth blocking Wave 2. Same call as camera's preview.

## Stage plan

- [x] **Stage 1a (this commit):** repo, `MobNotify` API at parity (+ pure
  `schedule_opts/1` seam), erl stubs, manifest (perms/gradle/frameworks/
  host_requirements), mob_push CONTRACT FIXTURES (see below), test suite,
  this document.
- [x] **Stage 1b (2026-06-11):** the three native layers extracted. iOS .m calls
  the NEW core export `mob_notify_set_screen_pid(ErlNifPid)`. Android: the
  shared state moved to the GENERATED `io.mob.plugin.MobNotifyHub` (written by
  mob_dev next to MobActivityAware) — the bridge sets `notifyPid`/drains
  `pendingToken`; host delivery code reads the hub. The alarm intent targets
  the host's NotificationReceiver via dynamic
  `setClassName(packageName + ".NotificationReceiver")`. `bridge_kt` added.
- [x] **Stage 2 (core strip, mob repo, merged 1f2b38a):** delete `lib/mob/notify.ex`, the 3 erl
  stubs, `ios/mob_nif.m:3238-3319`, the zig blocks + caches; ADD the
  `mob_notify_set_screen_pid` export next to the delegate (delivery stays).
  `take_launch_notification` + delegate + `mob_send_push_token` untouched.
- [x] **Stage 3 (template strip, mob_new, merged e6667e6):** remove `notify_*` from
  `MobBridge.kt.eex`; KEEP `MobFirebaseService.kt.eex`, the manifest
  `<service>`, `POST_NOTIFICATIONS`→ moves to plugin manifest (template drops
  it), AppDelegate push-token call, google-services wiring (host-level).
- [x] **Stage 4 (local notifications cross-platform; live push pending):** Android +
  iOS verified. iOS (iPhone SE 2026-06-11): :notifications authorization granted →
  schedule → banner → FOREGROUND DELIVERY back to the scheduling process through
  the mob_notify_set_screen_pid seam ({:notification, %{id, source: :local, data}}).
  GOTCHA worth keeping: an UNAUTHORIZED iOS app drops scheduled notifications
  SILENTLY — probes/tests must Mob.Permissions.request(:notifications) first
  (Android < 13 needs no grant, which masks this). Originally: ANDROID DONE (Moto G 2026-06-11, demo 20d4c34): first
  native compile zero-iteration; schedule → notification FIRED in the shade
  (plugin alarm → host receiver via the hub channel); cancel → never fired;
  register_push path clean (placeholder google-services.json → token fetch
  noop, expected; a real Firebase project is needed for a live token).
  REMAINING: iOS device build (USB replug), live push end-to-end with real
  APNs/FCM credentials + mob_push, signing, docs, CHANGELOG, and the
  recorded iOS source:"local" delegate drift fix.

## mob_push contract

`mob_push` (server, Hex 0.2.1) stays a SEPARATE package: different runtime,
zero shared deps, already published, explicitly mob-agnostic. The wire contract
is pinned by `test/fixtures/push_contract.exs`, vendored byte-identically in
BOTH repos (this repo + mob_push) — each side's suite asserts its own half:
mob_push that its payload builders produce these shapes; mob_notify that the
documented `handle_info` shapes match these fixtures. Update BOTH copies
together or the suites disagree.
