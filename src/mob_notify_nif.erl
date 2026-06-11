%% mob_notify_nif — Erlang NIF module for the notifications tier-1 plugin.
%%
%% iOS: priv/native/ios/mob_notify_nif.m (Objective-C: UNUserNotificationCenter
%% scheduling/cancel + registerForRemoteNotifications; the notification-center
%% DELEGATE + push-token forwarding + launch-notification handoff stay in mob
%% core — the plugin calls core's exported mob_notify_set_screen_pid). Android:
%% priv/native/jni/mob_notify_nif.zig bridging to NotificationManager /
%% AlarmManager / FirebaseMessaging via io.mob.notify.MobNotifyBridge. Both
%% register this module via ERL_NIF_INIT and are statically linked into the
%% host binary on device. On a host dev build neither is linked, so on_load
%% tolerates the failure and the NIFs fall back to nif_error until the native
%% merge links one.
-module(mob_notify_nif).
-export([
    notify_schedule/1,
    notify_cancel/1,
    notify_register_push/0
]).
-on_load(init/0).

init() ->
    case erlang:load_nif("mob_notify_nif", 0) of
        ok -> ok;
        {error, _} -> ok
    end.

notify_schedule(_OptsJson) ->
    erlang:nif_error(nif_not_loaded).

notify_cancel(_Id) ->
    erlang:nif_error(nif_not_loaded).

notify_register_push() ->
    erlang:nif_error(nif_not_loaded).
