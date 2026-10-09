# mob_notify — Agent Instructions

You're in **mob_notify**, a Mob plugin: the device-side surface for local notifications and push registration. Extracted from mob core's `Mob.Notify` in Wave 2. The API is `MobNotify.{schedule, cancel, register_push}/1`. Delivery of `{:notification, ...}` and `{:push_token, ...}` messages is core behaviour — this plugin owns scheduling, cancellation, and push registration only.

**Also read [`~/code/mob/AGENTS.md`](../mob/AGENTS.md)** for the system view — mob's three-repo topology, plugin manifest schema, `Mob.Composite` / `Mob.Sigil`, how to drive a running app, and the cross-cutting pre-empt-failure rules. See [`~/code/mob/MOB_PLUGINS.md`](../mob/MOB_PLUGINS.md) for the manifest schema. This file is mob_notify-specific.

> **Keep this file current.** When you change delivery behaviour, add a `host_requirements` entry, or hit a gotcha that would trip the next agent, fix it here in the same commit — not in a follow-up.

## What mob_notify is, in one paragraph

Device half of the notification story. `MobNotify.schedule/2` and `cancel/2` arm and cancel local notifications through iOS `UNUserNotificationCenter` and Android `AlarmManager` + `NotificationManager`. `MobNotify.register_push/1` calls `[UIApplication registerForRemoteNotifications]` on iOS and the FCM token API on Android, then the resulting token arrives at the calling process as `{:push_token, :ios | :android, token}`. That token is sent to your server, which uses `mob_push` to actually push. An arriving or tapped notification lands as `{:notification, notif}` (a `Mob.Notification` map with `presentation: :foreground | :tap`): every native path hands one JSON envelope to mob's router (core's `mob_deliver_notification` on Android), which decodes it and forwards it to the process registered here, else to the current screen (mob `decisions/2026-10-01-notification-delivery-envelope.md`). Local notifications reach it through mob core's notification-center delegate (iOS) and the host's `NotificationReceiver` / `MainActivity` (Android, mob_new 0.6.3 templates). Android pushes reach it through THIS plugin (MOB-327): `io.mob.notify.MobFirebaseService` (foreground arrivals + the banner Android doesn't show for a foreground app, token refreshes, forwarding `mob_wake_id` messages and tokens to mob_wake) and `MobNotifyFcm`, which reads the launch extras of a tap on a push the system tray showed (`google.message_id` + data keys) when the activity resumes and delivers each message id once. A tray tap carrying mob_push's `mob_notification_json` is left to the host MainActivity. The service's intent filter has priority -1, so an app's own `FirebaseMessagingService` wins over it.

## What mob_notify is NOT

* **Not `mob_push`.** `mob_push` is the SERVER side — APNs HTTP/2 + FCM v1 credentials, zero device code. `mob_notify` is the DEVICE side — schedule, cancel, register-for-push. Both are needed for a full remote-push flow, and they coordinate on the wire contract pinned by shared fixtures in `test/fixtures/push_contract.exs` (vendored byte-identically in both repos). If a fixture changes, update BOTH copies together or the two suites disagree.
* **Not `mob_wake`.** `mob_wake` is the SILENT-push (and OS scheduler) receive side. `mob_notify` is the user-visible-notification and token-registration side. The intersection: `MobNotify.register_push/1` produces the token that `mob_push` uses to send a `mob_wake` payload. See `mob_wake`'s moduledoc for the iOS silent-APNs preconditions.
* **Not `mob_background`.** `mob_background` keeps the app alive continuously while backgrounded. `mob_notify` doesn't affect app lifecycle — it just talks to the notification centre.
* **Not the notification-center delegate.** Local-notification delivery plumbing (`MobNotificationDelegate` / `g_notif_delegate` on iOS, the host's `NotificationReceiver` / `MainActivity` on Android, launch-notification handoff) STAYS IN mob CORE and the host templates. This plugin points deliveries at the calling process via the exported `mob_notify_set_screen_pid` (iOS) or the generated `io.mob.plugin.MobNotifyHub` (Android). Android PUSH receipt is the exception: it ships here (see above), because the template never shipped it. See `EXTRACTION.md` — the "descope line".

## Anatomy of the plugin

* `lib/mob_notify.ex` — public `MobNotify.{schedule, cancel, register_push, schedule_opts}/1`. Pure Elixir seam over the NIF stubs.
* `lib/mob_notify/self_test.ex` — `MobNotify.SelfTest` (`Mob.Plugin.SelfTest`, manifest `selftest:`), run by `mix mob.selftest` / mob_ci. It calls the read-only `notify_permission_status/0` NIF (never prompts, never posts); keep it free of anything that shows UI or leaves state. The NIF tables in the `.m` and `.zig` must list exactly the `.erl` stub's exports (a test enforces it).
* `src/mob_notify_nif.erl` — Erlang NIF stub (tolerant `on_load` so host tests without the NIF don't crash).
* `priv/mob_plugin.exs` — plugin manifest. Frameworks (`UserNotifications` iOS), permissions (`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED` Android), gradle deps (`firebase-messaging`), `manifest_application_snippets` (the `MobFirebaseService` `<service>` and `MobNotifyBootReceiver` `<receiver>`, spliced into the host manifest by mob_dev >= 0.6.19, skipped when the host declares the same name), `host_requirements`. **The `host_requirements` list is load-bearing** — every `mix mob.deploy --native` warns about them; keep it accurate as prerequisites shift.
* `priv/mob_plugin.pub` — Ed25519 public key. Signature regenerated in CI at publish.
* `priv/native/ios/mob_notify_nif.m` — iOS NIF (ObjC): `UNMutableNotificationContent` scheduling, `removePendingNotificationRequestsWithIdentifiers:`, `registerForRemoteNotifications`. Calls core-exported `mob_notify_set_screen_pid(ErlNifPid)`.
* `priv/native/jni/mob_notify_nif.zig` — Android NIF (zig): bridges to Kotlin via `CallStaticVoidMethod`; JNI thunks `nativeDeliverNotifyPushToken` and `nativeDeliverNotification` (→ core's exported `mob_deliver_notification`, mob >= 0.9.8).
* `priv/native/android/MobNotifyBridge.kt` — Kotlin bridge, ONE file (mob_dev copies and signs only `bridge_kt`). Talks to `AlarmManager`, `NotificationManager`, FCM `getToken()`. Also contains `MobNotifyBootReceiver` (re-arms alarms on `BOOT_COMPLETED`), shared `MobNotifySchedules` state, `MobFcmEnvelope` (pure envelope builder: org.json + stdlib only, so the host test can run it), `MobNotifyFcm` (foreground tracking via `ActivityLifecycleCallbacks`, tray-tap delivery on resume and through `androidx.core.app.OnNewIntentProvider` for a tap while already resumed, deduped by persisted message id, banner) and `MobFirebaseService`.
* `test/kotlin/` — `MobFcmEnvelopeRunner.kt` + compile-only Firebase / androidx.core stubs (add a stub when the bridge imports a new library class). `test/mob_fcm_envelope_test.exs` (tag `:kotlin_host`) compiles the bridge with `kotlinc` against the newest `android.jar`, runs `MobFcmEnvelope`, and decodes its output with mob's `Mob.Notification.decode/1`. Needs `kotlinc`, `kotlin`, an Android SDK platform and an org.json jar (Gradle cache, or `MOB_NOTIFY_ORG_JSON_JAR`); locally `test_helper.exs` excludes the tag and says why when one is missing. CI (`.github/workflows/test.yml`) downloads org.json from Maven Central and sets `MOB_NOTIFY_REQUIRE_KOTLIN_HOST=1`, which makes a missing toolchain fail the run instead.
* `test/fixtures/push_contract.exs` — the wire contract shared with mob_push. If you're changing the shape of `{:push_token, ...}` or the push payload the app expects, update BOTH copies of this fixture and run both suites.

## Cross-repo work

**mob (framework):** delivery plumbing lives here — `mob_notify_set_screen_pid` (iOS core export), the UN delegate, `mob_send_push_token` from the host AppDelegate. Any change to the `{:notification, ...}` or `{:push_token, ...}` shape lands in mob, not this plugin.

**mob_push:** the wire contract. Keep `test/fixtures/push_contract.exs` in sync between the two repos; each side asserts its own half.

**mob_new:** the host AppDelegate, `MainActivity` and `NotificationReceiver` templates ship the local-notification delivery wiring. mob_new does NOT generate a `MobFirebaseService` or the google-services Gradle wiring; push receipt ships in this plugin. If a new `host_requirements` entry is needed to make delivery work, land it in mob_new's template AND update this plugin's manifest.

**mob_wake:** silent-push delivery on iOS routes through the AppDelegate's `didReceiveRemoteNotification:fetchCompletionHandler:` (added in mob_new template via MOB-271). On Android, FCM goes to ONE service: this plugin's `MobFirebaseService` forwards `mob_wake_id` messages to `io.mob.wake.MobWakeBridge.onPushFired` and tokens to `onFcmTokenRefresh` by reflection. mob_wake's own `MobWakeFcmService`, if a host declares it (priority 0), takes FCM from this plugin's (priority -1). Changes to that dispatch should touch both this plugin and mob_wake's docs.

## Testing

Elixir suite:

```bash
mix deps.get
mix test
```

Covers manifest structure, permission declarations, host_requirements presence, and the push-contract fixture shape.

Native changes (.m / .zig / .kt) are only partly exercised by `mix test` (the `:kotlin_host` tests compile the Kotlin bridge and run `MobFcmEnvelope`; Activity/FCM behaviour still needs a device). Deploy against `~/code/mob_plugin_demo` (or another host that activates this plugin) and verify on device:

* Local: schedule a notification with `delay_seconds: 5`, background the app, confirm the banner fires.
* Push: `MobNotify.register_push(nil)` and confirm `{:push_token, :ios | :android, _}` arrives at the calling process; then send via `mob_push` from your server.

## The pre-empt-failure rules that matter here

1. **Local scheduling fails silently without permission.** iOS drops unauthorised `UNNotificationRequest`s with no error — always `Mob.Permissions.request(socket, :notifications)` before `schedule/2`. Android < 13 has no permission for POST_NOTIFICATIONS but 13+ requires it explicitly.
2. **Exact-alarm access is Android 12+ special-access.** `SCHEDULE_EXACT_ALARM` is declared but users must grant it in settings. The bridge falls back to `setAndAllowWhileIdle` (inexact) when `canScheduleExactAlarms()` returns false — the fallback is silent so tests must assert both branches exist in the Kotlin source (see `test/mob_notify_test.exs` "exact-alarm guard" describe block).
3. **Boot re-arm needs `MobNotifyBootReceiver` in the host manifest.** AlarmManager alarms are wiped on reboot; the receiver in `io.mob.notify.MobNotifyBootReceiver` re-arms persisted schedules on `ACTION_BOOT_COMPLETED`. The plugin manifest's `manifest_application_snippets` declares it (and `MobFirebaseService`); a host that already declares the same `android:name` keeps its own and gets no duplicate. A plugin component class must live in `bridge_kt`, and the `:kotlin_host` test checks every snippet's class is compiled from it.
4. **Push token forwarding is host-side.** The iOS AppDelegate must call `mob_send_push_token(hex)` from `didRegisterForRemoteNotificationsWithDeviceToken:`; without it, no `{:push_token, ...}` message ever arrives. Same story for `didFailToRegisterForRemoteNotificationsWithError:` — the template NSLogs it, and that's often the only signal when APNs registration silently fails.

## Pre-commit checklist

Same gate as mob core:

```bash
mix format
mix credo --strict       # includes ExSlop + jump_credo_checks
mix compile --warnings-as-errors
mix test
```

Native changes (`.m` / `.zig` / `.kt`) aren't exercised by `mix test` — they need a `mix mob.deploy --native` of a host app (mob_plugin_demo) and a device check before committing (see Testing).

Pre-push hook (`.githooks/pre-push`, `git config core.hooksPath .githooks` once per clone) runs format + credo + compile on every push and the full suite when `mix.exs` changes (release preflight).

## Release flow

`mix.exs` version bump on master triggers `.github/workflows/release.yml` (tag + GitHub Release + Hex publish, with the manifest signed against `priv/mob_plugin.pub`). Do NOT bump versions without explicit permission — see `~/code/mob/RELEASE.md` for the trigger model.
