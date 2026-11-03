package com.example.expencify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private var sMethodChannel: MethodChannel? = null
        private val executor = Executors.newSingleThreadExecutor()
        private const val CHANNEL_NAME = "com.example.expencify/native_sms"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        fun readPending(context: Context): List<Map<String, Any>> = PendingSmsStore.readPending(context)
        fun ack(context: Context, id: String) { PendingSmsStore.ack(context, id) }
        fun clearPending(context: Context) { PendingSmsStore.clear(context) }
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION || context == null) return

        if (!context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean("flutter.sms_tracking_enabled", false)) return
        val pendingResult = goAsync()
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)

        Log.d("EXPENCIFY_NATIVE", "SMS Broadcast received")

        executor.execute {
            try {
                // Android supplies multipart PDUs in order; assemble per sender.
                for ((sender, parts) in messages.groupBy { it.displayOriginatingAddress }) {
                    if (sender == null || parts.isEmpty()) continue
                    handleSms(context, sender, parts.joinToString("") { it.messageBody ?: "" }, parts.first().timestampMillis)
                }
            } catch (e: Exception) {
                Log.e("EXPENCIFY_NATIVE", "SMS queue operation failed; pending data was preserved")
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun handleSms(context: Context, sender: String, body: String, timestamp: Long) {
        if (!context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean("flutter.sms_tracking_enabled", false)) return
        // Persist before dispatch. A channel call alone is not an acknowledgement.
        val id = java.util.UUID.randomUUID().toString()
        savePendingSms(context, sender, body, timestamp, id)
        SmsProcessingWorker.enqueue(context)
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
                        mapOf("sender" to sender, "body" to body, "timestamp" to timestamp),
                        object : MethodChannel.Result {
                            override fun success(result: Any?) { if (result == true) ack(context, id) }
                            override fun error(code: String, message: String?, details: Any?) { }
                            override fun notImplemented() { }
                        }
                    )
                    Log.d("EXPENCIFY_NATIVE", "✓ Sent via Main Engine")
                } catch (e: Exception) {
                    Log.e("EXPENCIFY_NATIVE", "MethodChannel dispatch failed", e)
                    // Fallback: save to pending queue so we don't lose the SMS
                    // The already persisted message will retry on next launch.
                }
            }
        } else {
            // The receiver never launches Flutter. WorkManager processes the durable queue.
            Log.d("EXPENCIFY_NATIVE", "App is closed. Saving SMS to pending queue.")
            // The message is already durable in the pending queue.
        }
    }

    private fun savePendingSms(context: Context, sender: String, body: String, timestamp: Long, id: String) {
        PendingSmsStore.enqueue(context, id, sender, body, timestamp)
    }
}
