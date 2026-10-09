%{
  name: :mob_notify,
  # The mob dep in mix.exs floors at 0.9.15 (Mob.Plugin.SelfTest); 0.9.8 is
  # what delivers the `{:notification, map}` envelope this plugin documents
  # (MOB-315).
  mob_version: "~> 0.9",
  plugin_spec_version: 1,
  # On-device proof for `mix mob.selftest` / mob_ci: a read-only
  # notify_permission_status/0 through the NIF (see Mob.Plugin.SelfTest).
  selftest: MobNotify.SelfTest,
  description:
    "Local + push notifications (device half) — extracted from mob core in Wave 2. " <>
      "Pairs with the server-side mob_push package.",
  nifs: [
    # iOS: Objective-C NIF — UNUserNotificationCenter scheduling/cancel +
    # registerForRemoteNotifications. The notification-center DELEGATE, push-token
    # forwarding (mob_send_push_token) and launch-notification handoff
    # (take_launch_notification, consumed by core Mob.Screen) STAY IN CORE; this
    # NIF calls core's exported mob_notify_set_screen_pid. lang: :objc;
    # platform: :ios so it isn't pulled into the Android build.
    %{module: :mob_notify_nif, native_dir: "priv/native/ios", lang: :objc, platform: :ios},
    # Android: zig NIF bridging to NotificationManager/AlarmManager/FCM via the
    # Kotlin io.mob.notify.MobNotifyBridge.
    %{module: :mob_notify_nif, native_dir: "priv/native/jni", lang: :zig, platform: :android}
  ],
  # NOTE: the :notifications runtime-permission CAPABILITY stays in core for now
  # (its request flow is part of core's permission enum on both platforms and is
  # used by core delivery). Revisit when the permission registry owns all caps.
  android: %{
    bridge_kt: "priv/native/android/MobNotifyBridge.kt",
    bridge_class: "io.mob.notify.MobNotifyBridge",
    permissions: [
      "android.permission.POST_NOTIFICATIONS",
      # Exact-alarm scheduling (setExactAndAllowWhileIdle). Special-access on
      # Android 13+; notify_schedule falls back to an inexact alarm when the user
      # hasn't granted it. The plugin declares the permission it uses rather than
      # leaning on the host manifest.
      "android.permission.SCHEDULE_EXACT_ALARM",
      # Boot re-arm. AlarmManager alarms are wiped on reboot; MobNotifyBootReceiver
      # re-arms persisted schedules on ACTION_BOOT_COMPLETED, which requires this
      # permission. The <receiver> is declared by manifest_application_snippets.
      "android.permission.RECEIVE_BOOT_COMPLETED"
    ],
    gradle_deps: [
      # FCM client. The google-services GRADLE PLUGIN + google-services.json are
      # host-level (see host_requirements) — a plugin manifest can't contribute
      # buildscript classpath entries.
      "com.google.firebase:firebase-messaging:24.0.0"
    ],
    # Spliced into the host's <application> by mob_dev's native build (mob_dev
    # >= 0.6.19; skipped when the host already declares the same android:name).
    # Both classes ship in bridge_kt.
    manifest_application_snippets: [
      # FCM receipt (MOB-327): token refresh, foreground arrivals, mob_wake
      # forwarding. Priority -1: Android hands FCM to one service, and an app
      # that declares its own MESSAGING_EVENT service (priority 0) keeps it;
      # firebase-messaging's own fallback service sits at -500.
      """
      <service android:name="io.mob.notify.MobFirebaseService"
          android:exported="false">
          <intent-filter android:priority="-1">
              <action android:name="com.google.firebase.MESSAGING_EVENT" />
          </intent-filter>
      </service>
      """,
      # Boot re-arm of scheduled notifications. exported: BOOT_COMPLETED comes
      # from the system.
      """
      <receiver android:name="io.mob.notify.MobNotifyBootReceiver"
          android:exported="true">
          <intent-filter>
              <action android:name="android.intent.action.BOOT_COMPLETED" />
          </intent-filter>
      </receiver>
      """
    ]
  },
  ios: %{
    frameworks: ["UserNotifications"]
    # No plist key: notification permission has no usage-description string.
  },
  # Manual host-app steps the build can't automate; printed as a warning on
  # every `mix mob.deploy --native` of the host. mob_new-generated apps satisfy
  # the NotificationReceiver and AppDelegate ones (the silent-APNs background
  # mode needs mob_new >= 0.6.1). The Firebase wiring (google-services plugin +
  # json, per Firebase project) and the Apple Developer Portal step are always
  # manual.
  host_requirements: [
    "Android: the host build.gradle needs the com.google.gms.google-services plugin " <>
      "+ a google-services.json (Firebase console) — buildscript classpath entries " <>
      "are host-level, a plugin manifest can't contribute them.",
    "iOS: the host AppDelegate must forward the APNs device token: in " <>
      "didRegisterForRemoteNotificationsWithDeviceToken call mob_send_push_token(hex) " <>
      "(exported by mob core; the mob_new template ships this wired).",
    "iOS silent APNs (mob_push -> mob_wake style): the host Info.plist needs " <>
      "UIBackgroundModes.remote-notification (generated by mob_new >= 0.6.1; " <>
      "older apps must add it by hand) — without it iOS won't wake a " <>
      "backgrounded app on a content-available push.",
    "iOS silent APNs (Apple Developer, out-of-band): the App ID must have " <>
      "Push Notifications capability enabled in Apple Developer Portal, and its " <>
      "provisioning profile must be regenerated afterwards. mob_dev's " <>
      "resolve_or_generate_entitlements/4 reads aps-environment from the " <>
      "embedded.mobileprovision — if the profile doesn't grant it, no APNs " <>
      "device token will ever be issued and MobNotify.register_push silently " <>
      "does nothing (didFailToRegisterForRemoteNotificationsWithError is the " <>
      "surface — the mob_new AppDelegate template NSLogs it).",
    "Android: scheduled notifications display via a <applicationId>.NotificationReceiver " <>
      "BroadcastReceiver declared in AndroidManifest (the mob_new template ships it) — " <>
      "display/tap delivery stays host-side; this plugin only arms the alarm."
  ]
}
