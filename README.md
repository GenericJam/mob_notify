# mob_notify

Local and push notifications for apps built with [Mob](https://hexdocs.pm/mob)
— the device half of `Mob.Notify`, extracted from mob core as a plugin. Owns
scheduling, cancellation, and push registration; pairs with the server-side
[mob_push](https://hex.pm/packages/mob_push) package for sending.

## Installation

```elixir
# mix.exs
{:mob_notify, "~> 0.1"}

# mob.exs
config :mob, :plugins, [:mob_notify]
```

Requires the `:notifications` permission
(`Mob.Permissions.request(socket, :notifications)`). Android 13+'s
`POST_NOTIFICATIONS` and the `firebase-messaging` gradle dep are merged from
this plugin's manifest; iOS needs no plist key.

## Usage

Local notifications:

```elixir
MobNotify.schedule(socket,
  id:    "reminder_1",
  title: "Time to check in",
  body:  "Open the app to see today's updates",
  at:    ~U[2026-04-16 09:00:00Z],   # or delay_seconds: 60
  data:  %{screen: "reminders"}
)

MobNotify.cancel(socket, "reminder_1")

def handle_info({:notification, %{id: id, data: data, source: :local}}, socket), do: ...
```

Push registration (call once after `:notifications` is granted):

```elixir
socket = MobNotify.register_push(socket)

def handle_info({:push_token, platform, token}, socket) do
  # platform is :ios | :android — store both, send with MobPush.send/3 server-side
end

def handle_info({:notification, %{title: t, body: b, data: d, source: :push}}, socket), do: ...
```

Notifications arrive via `handle_info` regardless of app state — foreground,
background, or relaunched after being killed. Delivery plumbing lives in mob
core; this plugin is the API surface.

## Host app requirements

Four manual steps the build can't automate. **mob_new-generated apps already
satisfy all of them via their templates**; hand-rolled hosts must add:

1. **Android — FCM service**: `AndroidManifest.xml` must declare
   `<service android:name=".MobFirebaseService" android:exported="false">`
   with the `com.google.firebase.MESSAGING_EVENT` intent filter. The
   `MobFirebaseService.kt` class ships in the host app, not this plugin
   (`FirebaseMessagingService` subclasses must live in the host package).
2. **Android — Firebase wiring**: the host `build.gradle` needs the
   `com.google.gms.google-services` plugin + a `google-services.json` from
   the Firebase console (buildscript classpath entries are host-level).
3. **iOS — APNs token forwarding**: the host AppDelegate must call
   `mob_send_push_token(hex)` (exported by mob core) in
   `didRegisterForRemoteNotificationsWithDeviceToken`.
4. **Android — display receiver**: scheduled notifications display via a
   `<applicationId>.NotificationReceiver` BroadcastReceiver declared in
   `AndroidManifest.xml` — this plugin only arms the alarm.

## Limits

- Local scheduling is device-verified on both platforms. Live remote push
  needs real APNs/FCM credentials plus the mob_push server side.
- An **unauthorized iOS app drops scheduled notifications silently** —
  request `:notifications` before scheduling.
- The wire contract with mob_push is pinned by shared fixtures
  (`test/fixtures/push_contract.exs`, vendored identically in both repos).

## Development

Clone, then run once:

```bash
mix setup
```

That fetches deps and activates the repo's git hooks (`.githooks/pre-push`):
`mix format --check`, `mix credo --strict` (incl. ExSlop), and `mix compile --warnings-as-errors` run on every push, plus the full test
suite when `mix.exs` changes — the same gate CI enforces before publishing.

## License

MIT
