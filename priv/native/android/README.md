# Stage 1b placeholder

`MobNotifyBridge.kt` lands here in Stage 1b — the notify_schedule /
notify_cancel / notify_register_push Kotlin from mob_new's `MobBridge.kt.eex`
(~1450-1520), as a plugin-owned object (package io.mob.notify) with its own
deliver thunks. `MobFirebaseService` stays a HOST class (see EXTRACTION.md +
the manifest's host_requirements). Once this lands, add `bridge_kt` +
`bridge_class` to ../../mob_plugin.exs.
