// Host-JVM driver for MobFcmEnvelope (priv/native/android/MobNotifyBridge.kt).
// Reads a JSON array of calls from the file named by args[0] and prints a JSON
// array of their results, in order:
//
//   {"fn": "tap", "extras": {...}}
//     → {"envelope": <string or null>, "copiedExtras": <bool>}, the way
//       MobNotifyFcm.deliverTap reads a launch intent's extras
//   {"fn": "fromMessage", "messageId": ..., "title": ..., "body": ...,
//    "data": {...}, "presentation": "foreground" | "tap"} → the envelope string
//
// Driven by test/mob_fcm_envelope_test.exs.
package io.mob.notify.test

import io.mob.notify.MobFcmEnvelope
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

fun main(args: Array<String>) {
    val calls = JSONArray(File(args[0]).readText())
    val out = JSONArray()
    for (i in 0 until calls.length()) {
        val call = calls.getJSONObject(i)
        val result: Any? = when (val fn = call.getString("fn")) {
            "tap" -> {
                val extras = values(call.getJSONObject("extras"))
                var copied = false
                val tap = MobFcmEnvelope.tap(
                    extras[MobFcmEnvelope.MESSAGE_ID] as? String,
                    extras.containsKey(MobFcmEnvelope.MOB_JSON),
                ) {
                    copied = true
                    extras
                }
                JSONObject().put("envelope", tap?.second ?: JSONObject.NULL).put("copiedExtras", copied)
            }
            "fromMessage" -> MobFcmEnvelope.fromMessage(
                call.optStringOrNull("messageId"),
                call.optStringOrNull("title"),
                call.optStringOrNull("body"),
                values(call.getJSONObject("data")).mapValues { it.value.toString() },
                call.getString("presentation"),
            )
            else -> error("unknown fn $fn")
        }
        out.put(result ?: JSONObject.NULL)
    }
    println(out.toString())
}

// Launch extras keep their Bundle types (google.sent_time is a Long), so
// numbers stay numbers here.
private fun values(obj: JSONObject): Map<String, Any?> =
    obj.keys().asSequence().associateWith { key -> obj.get(key).takeUnless { it == JSONObject.NULL } }

private fun JSONObject.optStringOrNull(key: String): String? =
    if (isNull(key)) null else getString(key)
