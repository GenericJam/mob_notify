defmodule MobNotify do
  @moduledoc """
  Local and push notifications — the device half, extracted from mob core's
  `Mob.Notify` in Wave 2.

  Requires `:notifications` permission (request via `Mob.Permissions.request/2`).
  No `Info.plist` key needed on iOS. Android 13+ (API 33) requires
  `POST_NOTIFICATIONS`, declared by this plugin's manifest.

  All notifications arrive via `handle_info` regardless of app state (foreground,
  background, or relaunched after being killed). Delivery plumbing (the
  notification-center delegate, push-token forwarding, launch-notification
  handoff) lives in mob CORE — this plugin owns scheduling, cancellation, and
  push registration.

  ## Local notifications

      MobNotify.schedule(socket,
        id:    "reminder_1",
        title: "Time to check in",
        body:  "Open the app to see today's updates",
        at:    ~U[2027-04-16 09:00:00Z],   # or delay_seconds: 60
        data:  %{screen: "reminders"}
      )

      MobNotify.cancel(socket, "reminder_1")

      def handle_info({:notification, %{id: id, data: data, source: :local}}, socket), do: ...

  ## Push notifications (pairs with the `mob_push` package on your server)

      # Call once after :notifications permission granted
      MobNotify.register_push(socket)

      def handle_info({:push_token, :ios,     token}, socket), do: ...
      def handle_info({:push_token, :android, token}, socket), do: ...

      def handle_info({:notification, %{title: t, body: b, data: d, source: :push}}, socket), do: ...

  `mob_push` is deliberately a SEPARATE package — it runs on your server (APNs
  HTTP/2 + FCM v1) with zero device/NIF code. The wire contract between the two
  is pinned by shared fixtures in `test/fixtures/push_contract.exs`, vendored
  identically in both repos.

  iOS: `UNUserNotificationCenter`. Android: `NotificationManager` + `AlarmManager` + FCM.
  """

  @doc """
  Schedule a local notification.

  Options:
    - `id:` (required) — string identifier, used to cancel the notification
    - `title:` (required) — notification title
    - `body:` (required) — notification body text
    - `at: %DateTime{}` — absolute trigger time (UTC)
    - `delay_seconds: integer` — trigger after N seconds (alternative to `at:`)
    - `data: %{}` — arbitrary map passed back in the `handle_info` payload
  """
  @spec schedule(Mob.Socket.t(), keyword()) :: Mob.Socket.t()
  def schedule(socket, opts) do
    :mob_notify_nif.notify_schedule(:json.encode(schedule_opts(opts)))
    socket
  end

  @doc """
  Build the option map passed to `notify_schedule/1`. Pure function exposed so
  tests can pin defaults + serialisation without going through the NIF.
  """
  @spec schedule_opts(keyword()) :: map()
  def schedule_opts(opts) do
    id = Keyword.fetch!(opts, :id)
    title = Keyword.fetch!(opts, :title)
    body = Keyword.fetch!(opts, :body)
    data = Keyword.get(opts, :data, %{})

    trigger_at =
      case opts[:at] do
        %DateTime{} = dt -> DateTime.to_unix(dt)
        nil -> DateTime.to_unix(DateTime.utc_now()) + (opts[:delay_seconds] || 0)
      end

    %{
      "id" => id,
      "title" => title,
      "body" => body,
      "trigger_at" => trigger_at,
      "data" => Map.new(data, fn {k, v} -> {to_string(k), v} end)
    }
  end

  @doc """
  Cancel a pending local notification by its id.
  Has no effect if the notification has already been delivered.
  """
  @spec cancel(Mob.Socket.t(), String.t()) :: Mob.Socket.t()
  def cancel(socket, id) do
    :mob_notify_nif.notify_cancel(id)
    socket
  end

  @doc """
  Register this device for push notifications.

  The device token arrives as `{:push_token, platform, token_string}` where
  `platform` is `:ios` or `:android`.

  Send this token to your server and use the `mob_push` library to send
  notifications to it.
  """
  @spec register_push(Mob.Socket.t()) :: Mob.Socket.t()
  def register_push(socket) do
    :mob_notify_nif.notify_register_push()
    socket
  end
end
