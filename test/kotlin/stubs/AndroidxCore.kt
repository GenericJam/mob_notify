// Compile-only stand-ins for the androidx.core types MobNotifyBridge.kt uses
// (the host app gets the real ones through androidx.activity); see
// PlayServicesTasks.kt.
package androidx.core.util

fun interface Consumer<T> {
    fun accept(value: T)
}
