// Compile-only stand-ins for the firebase-messaging / play-services-tasks
// classes MobNotifyBridge.kt uses, so test/mob_fcm_envelope_test.exs can
// compile the bridge on the host JVM against android.jar. Never run: the
// scenarios exercise MobFcmEnvelope, which touches only org.json. Signatures
// mirror the real API as Kotlin sees it. (FirebaseMessaging.kt: the rest.)
package com.google.android.gms.tasks

abstract class Task<T> {
    abstract val isSuccessful: Boolean
    abstract val result: T
    abstract fun addOnCompleteListener(listener: OnCompleteListener<T>): Task<T>
}

fun interface OnCompleteListener<T> {
    fun onComplete(task: Task<T>)
}
