defmodule MobNotify.SelfTest do
  @moduledoc """
  The plugin's on-device proof (`Mob.Plugin.SelfTest`), run by
  `mix mob.selftest` and mob_ci for every activated plugin.

  One read-only native call, no UI: `:mob_notify_nif.notify_permission_status/0`
  asks the platform for this app's notification authorization. It never
  prompts, never posts and changes no state.

    * iOS: `UNUserNotificationCenter getNotificationSettings`, whose
      `authorizationStatus` comes back as `{:ok, :authorized | :denied |
      :not_determined | :provisional | :ephemeral}`.
    * Android: the Kotlin `MobNotifyBridge.notify_permission_status()`,
      answering from `NotificationManager.areNotificationsEnabled()` with
      `{:ok, :authorized | :denied}`. It goes through the bridge's cached
      jclass and the Activity the bootstrap hands it, so an answer proves the
      zig NIF is linked, `nativeRegister` ran and `setActivity` was called.

  Any of the statuses above is a pass: the status is the user's choice, the
  answer is the proof. `:denied` and `:not_determined` are not skips, because
  nothing here needs the permission.

  Failures: `{:error, :bridge_not_registered}` (Android: the bootstrap never
  called `MobNotifyBridge.register()`, or a method-ID lookup failed; schedule,
  cancel and register_push answer the same instead of aborting the VM),
  `{:error, :no_activity}` (the bridge has no Activity, so `schedule/2` and
  `cancel/2` would silently do nothing), `{:error, :query_failed}` (Android:
  the Kotlin query threw), `{:error, :timeout}` (iOS: the notification center
  didn't answer within 2 s), any other answer (including a status this module
  doesn't know), the host stub's `nif_not_loaded` (the NIF is not linked into
  the build) and a missing `:mob_notify_nif` module.
  """
  @behaviour Mob.Plugin.SelfTest

  @statuses [:authorized, :denied, :not_determined, :provisional, :ephemeral]

  @impl true
  def run(_ctx) do
    classify(:mob_notify_nif.notify_permission_status())
  rescue
    e in ErlangError ->
      {:fail, "mob_notify_nif is not linked into this build: #{Exception.message(e)}"}

    e in UndefinedFunctionError ->
      {:fail, "mob_notify_nif is missing from this build: #{Exception.message(e)}"}
  end

  @doc false
  # The classification of notify_permission_status/0's answer.
  @spec classify(term()) :: Mob.Plugin.SelfTest.result()
  def classify({:ok, status}) when status in @statuses, do: :pass

  def classify({:error, :bridge_not_registered}) do
    {:fail,
     "Kotlin MobNotifyBridge not registered (nativeRegister never ran or a method-ID lookup failed)"}
  end

  def classify({:error, :no_activity}) do
    {:fail, "MobNotifyBridge has no Activity (MobActivityAware.setActivity never called)"}
  end

  def classify({:error, :timeout}) do
    {:fail, "UNUserNotificationCenter did not answer getNotificationSettings within 2 s"}
  end

  def classify(other) do
    {:fail,
     "notify_permission_status/0 returned #{inspect(other)}, expected {:ok, status} " <>
       "with status in #{inspect(@statuses)}"}
  end
end
