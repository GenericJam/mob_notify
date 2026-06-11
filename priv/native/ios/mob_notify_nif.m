// mob_notify plugin — iOS NIF (UNUserNotificationCenter scheduling/cancel +
// remote-notification registration).
//
// Extracted from mob-core ios/mob_nif.m nif_notify_schedule / nif_notify_cancel
// / nif_notify_register_push (lines 3238-3319 pre-strip). DELIVERY stays in
// core: the UNUserNotificationCenter DELEGATE, push-token forwarding
// (mob_send_push_token, called by the host AppDelegate) and the
// launch-notification handoff (consumed by core Mob.Screen) all live in
// mob_nif.m. This NIF points core's delegate at the calling screen process via
// the exported mob_notify_set_screen_pid — the iOS counterpart of the Android
// io.mob.plugin.MobNotifyHub seam.
//
// Statically linked into the host binary (ERL_NIF_INIT + the generated
// driver_tab); compiled by the host build via -Dplugin_c_nifs through
// addObjcObject (Apple clang).
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#include "erl_nif.h"
#include <stdlib.h>
#include <string.h>

// Core export (mob ios/mob_nif.m): ensures the core-owned notification-center
// delegate exists and points deliveries at pid. Added in the notify core strip.
extern void mob_notify_set_screen_pid(ErlNifPid pid);

static ERL_NIF_TERM nif_notify_schedule(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary bin;
    if (!enif_inspect_binary(env, argv[0], &bin) &&
        !enif_inspect_iolist_as_binary(env, argv[0], &bin))
        return enif_make_badarg(env);
    ErlNifPid pid;
    enif_self(env, &pid);
    mob_notify_set_screen_pid(pid);

    // Copy JSON to heap-allocated buffer for use in async block
    char *json = (char *)malloc(bin.size + 1);
    memcpy(json, bin.data, bin.size);
    json[bin.size] = 0;

    dispatch_async(dispatch_get_main_queue(), ^{
      NSData *data = [NSData dataWithBytes:json length:strlen(json)];
      free(json);
      NSDictionary *opts = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if (!opts)
          return;

      UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
      content.title = opts[@"title"] ?: @"";
      content.body = opts[@"body"] ?: @"";
      NSDictionary *dataMap = opts[@"data"];
      if ([dataMap isKindOfClass:[NSDictionary class]])
          content.userInfo = dataMap;
      content.sound = [UNNotificationSound defaultSound];

      NSTimeInterval delay =
          [opts[@"trigger_at"] doubleValue] - [[NSDate date] timeIntervalSince1970];
      if (delay < 1)
          delay = 1;
      UNTimeIntervalNotificationTrigger *trigger =
          [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:delay repeats:NO];
      NSString *nid = opts[@"id"] ?: [[NSUUID UUID] UUIDString];
      UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:nid
                                                                        content:content
                                                                        trigger:trigger];
      [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req
                                                             withCompletionHandler:nil];
    });
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_notify_cancel(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary bin;
    if (!enif_inspect_binary(env, argv[0], &bin) &&
        !enif_inspect_iolist_as_binary(env, argv[0], &bin))
        return enif_make_badarg(env);
    NSString *nid = [[NSString alloc] initWithBytes:bin.data
                                             length:bin.size
                                           encoding:NSUTF8StringEncoding];
    dispatch_async(dispatch_get_main_queue(), ^{
      [[UNUserNotificationCenter currentNotificationCenter]
          removePendingNotificationRequestsWithIdentifiers:@[ nid ]];
    });
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_notify_register_push(ErlNifEnv *env, int argc,
                                             const ERL_NIF_TERM argv[]) {
    ErlNifPid pid;
    enif_self(env, &pid);
    mob_notify_set_screen_pid(pid);
    dispatch_async(dispatch_get_main_queue(), ^{
      [[UIApplication sharedApplication] registerForRemoteNotifications];
      // Token is delivered via AppDelegate didRegisterForRemoteNotificationsWithDeviceToken,
      // which calls core's mob_send_push_token (wired in the mob_new template).
    });
    return enif_make_atom(env, "ok");
}

static ErlNifFunc nif_funcs[] = {
    {"notify_schedule", 1, nif_notify_schedule, 0},
    {"notify_cancel", 1, nif_notify_cancel, 0},
    {"notify_register_push", 0, nif_notify_register_push, 0},
};

ERL_NIF_INIT(mob_notify_nif, nif_funcs, NULL, NULL, NULL, NULL)
