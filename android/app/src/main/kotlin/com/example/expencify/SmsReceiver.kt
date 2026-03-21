package com.example.expencify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private var sMethodChannel: MethodChannel? = null
        private val executor = Executors.newSingleThreadExecutor()
        private const val CHANNEL_NAME = "com.example.expencify/native_sms"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val PREFS_KEY = "flutter.pending_sms_list"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION || context == null) return

        val pendingResult = goAsync()
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)

        Log.d("EXPENCIFY_NATIVE", "SMS Broadcast received")

        executor.execute {
            try {
                for (msg in messages) {
                    val body = msg.messageBody ?: continue
                    val sender = msg.displayOriginatingAddress ?: continue
                    val timestamp = msg.timestampMillis

                    Log.d("EXPENCIFY_NATIVE", "Processing SMS from $sender...")
                    handleSms(context, sender, body, timestamp)
                }
            } catch (e: Exception) {
                Log.e("EXPENCIFY_NATIVE", "Error processing SMS", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun handleSms(context: Context, sender: String, body: String, timestamp: Long) {
        val cache = FlutterEngineCache.getInstance()
        val mainEngine = cache.get("main_engine")

        if (mainEngine != null && mainEngine.dartExecutor.isExecutingDart) {
            // App is open — dispatch directly via MethodChannel on the UI thread
            Log.d("EXPENCIFY_NATIVE", "App is open. Dispatching via MethodChannel.")
            Handler(Looper.getMainLooper()).post {
                try {
                    sMethodChannel = MethodChannel(mainEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
                    sMethodChannel?.invokeMethod(
                        "onSmsReceived",
                        mapOf("sender" to sender, "body" to body, "timestamp" to timestamp)
                    )
                    Log.d("EXPENCIFY_NATIVE", "✓ Sent via Main Engine")
                } catch (e: Exception) {
                    Log.e("EXPENCIFY_NATIVE", "MethodChannel dispatch failed", e)
                    // Fallback: save to pending queue so we don't lose the SMS
                    savePendingSms(context, sender, body, timestamp)
                }
            }
        } else {
            // App is CLOSED — do NOT start a FlutterEngine (causes ANR).
            // Save to SharedPreferences and let the app process it on next launch.
            Log.d("EXPENCIFY_NATIVE", "App is closed. Saving SMS to pending queue.")
            savePendingSms(context, sender, body, timestamp)
        }
    }

    private fun savePendingSms(context: Context, sender: String, body: String, timestamp: Long) {
        try {
            val prefs: SharedPreferences = context.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            val existing = prefs.getString(PREFS_KEY, "[]")
            val list = JSONArray(existing)

            val item = JSONObject().apply {
                put("sender", sender)
                put("body", body)
                put("timestamp", timestamp)
            }
            list.put(item)

            prefs.edit().putString(PREFS_KEY, list.toString()).apply()
            Log.d("EXPENCIFY_NATIVE", "✓ SMS saved to pending queue (${list.length()} total)")
        } catch (e: Exception) {
            Log.e("EXPENCIFY_NATIVE", "Failed to save pending SMS", e)
        }
    }
}
