%{
  name: :mob_notify,
  mob_version: "~> 0.6",
  plugin_spec_version: 1,
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
      "android.permission.POST_NOTIFICATIONS"
    ],
    gradle_deps: [
      # FCM client. The google-services GRADLE PLUGIN + google-services.json are
      # host-level (see host_requirements) — a plugin manifest can't contribute
      # buildscript classpath entries.
      "com.google.firebase:firebase-messaging:24.0.0"
    ]
  },
  ios: %{
    frameworks: ["UserNotifications"]
    # No plist key: notification permission has no usage-description string.
  },
  # Manual host-app steps the build can't automate; printed as a warning on
  # every `mix mob.deploy --native` of the host. mob_new-generated apps already
  # satisfy all of these via their templates.
  host_requirements: [
    "Android: AndroidManifest.xml must declare the FCM service inside <application>: " <>
      ~s(<service android:name=".MobFirebaseService" android:exported="false"> ) <>
      ~s(<intent-filter><action android:name="com.google.firebase.MESSAGING_EVENT" /></intent-filter></service>) <>
      " — the MobFirebaseService.kt class ships in the host app (mob_new template), " <>
      "not in this plugin (FirebaseMessagingService subclasses must live in the host package).",
    "Android: the host build.gradle needs the com.google.gms.google-services plugin " <>
      "+ a google-services.json (Firebase console) — buildscript classpath entries " <>
      "are host-level, a plugin manifest can't contribute them.",
    "iOS: the host AppDelegate must forward the APNs device token: in " <>
      "didRegisterForRemoteNotificationsWithDeviceToken call mob_send_push_token(hex) " <>
      "(exported by mob core; the mob_new template ships this wired).",
    "Android: scheduled notifications display via a <applicationId>.NotificationReceiver " <>
      "BroadcastReceiver declared in AndroidManifest (the mob_new template ships it) — " <>
      "display/tap delivery stays host-side; this plugin only arms the alarm."
  ]
}
