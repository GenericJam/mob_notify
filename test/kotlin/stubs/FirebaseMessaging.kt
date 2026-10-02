// Compile-only stand-ins; see PlayServicesTasks.kt.
package com.google.firebase.messaging

import android.content.Intent
import android.os.IBinder
import com.google.android.gms.tasks.Task

abstract class FirebaseMessagingService : android.app.Service() {
    open fun onNewToken(token: String) {}
    open fun onMessageReceived(message: RemoteMessage) {}
    override fun onBind(intent: Intent?): IBinder? = null
}

class RemoteMessage(
    val data: Map<String, String>,
    val messageId: String?,
    val notification: Notification?,
) {
    class Notification(val title: String?, val body: String?, val channelId: String?)
}

abstract class FirebaseMessaging {
    abstract val token: Task<String>

    companion object {
        @JvmStatic
        fun getInstance(): FirebaseMessaging = throw UnsupportedOperationException("stub")
    }
}
