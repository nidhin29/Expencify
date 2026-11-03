package com.example.expencify

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.*
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Semaphore
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Work owns a short-lived engine; the broadcast receiver only persists and enqueues. */
class SmsProcessingWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private val done = CountDownLatch(1)
    private val success = AtomicBoolean(false)
    private val finished = AtomicBoolean(false)

    override fun doWork(): Result {
        if (!processing.tryAcquire()) return Result.retry()
        val started = android.os.SystemClock.elapsedRealtime()
        val cpu = android.os.Process.getElapsedCpuTime()
        var outcome = "retry"
        try {
            if (!enabled(applicationContext) || PendingSmsStore.readPending(applicationContext).isEmpty()) {
                outcome = "skipped"
                return Result.success()
            }
            main.post {
                if (!finished.get()) try {
                    val active = FlutterEngineCache.getInstance().get("main_engine")
                    if (active != null && active.dartExecutor.isExecutingDart) {
                        MethodChannel(active.dartExecutor.binaryMessenger, "com.example.expencify/native_sms")
                            .invokeMethod("processPendingSms", null, object : MethodChannel.Result {
                                override fun success(result: Any?) { success.set(result == true); done.countDown() }
                                override fun error(code: String, message: String?, details: Any?) { done.countDown() }
                                override fun notImplemented() { done.countDown() }
                            })
                        return@post
                    }
                    val loader = FlutterInjector.instance().flutterLoader()
                    loader.startInitialization(applicationContext)
                    loader.ensureInitializationComplete(applicationContext, null)
                    val flutter = FlutterEngine(applicationContext)
                    engine = flutter
                    MethodChannel(flutter.dartExecutor.binaryMessenger, "com.example.expencify/native_sms")
                        .setMethodCallHandler { call, result ->
                            try {
                                when (call.method) {
                                    "readPendingSms" -> result.success(if (enabled(applicationContext)) PendingSmsStore.readPending(applicationContext) else emptyList<Map<String, Any>>())
                                    "ackPendingSms" -> { PendingSmsStore.ack(applicationContext, call.argument<String>("id") ?: ""); result.success(null) }
                                    "smsWorkFinished" -> { success.set(call.arguments == true); result.success(null); done.countDown() }
                                    else -> result.notImplemented()
                                }
                            } catch (_: Exception) { result.error("SMS_WORK", "Protected SMS processing will retry.", null) }
                        }
                    flutter.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "package:expencify/application/services/sms/background_sms_handler.dart", "smsWorkDispatcher"))
                } catch (_: Exception) { done.countDown() }
            }
            done.await(100, TimeUnit.SECONDS)
            if (success.get()) outcome = "success"
            return if (success.get()) Result.success() else Result.retry()
        } catch (_: Exception) { return Result.retry() }
        finally {
            cleanup(); processing.release()
            DiagnosticsSamples.record(applicationContext, android.os.SystemClock.elapsedRealtime() - started,
                android.os.Process.getElapsedCpuTime() - cpu, outcome)
        }
    }

    override fun onStopped() { done.countDown(); cleanup() }
    private fun cleanup() {
        finished.set(true)
        main.post { engine?.destroy(); engine = null }
    }

    companion object {
        private val processing = Semaphore(1)
        private const val WORK = "spendy.sms.process"
        private const val RETRY = "spendy.sms.retry"
        private fun enabled(context: Context) = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.sms_tracking_enabled", false)
        fun enqueue(context: Context) {
            val request = OneTimeWorkRequestBuilder<SmsProcessingWorker>()
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            // Pre-Android 12 expedited work requires a foreground notification.
            if (android.os.Build.VERSION.SDK_INT >= 31) request.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            WorkManager.getInstance(context).enqueueUniqueWork(WORK, ExistingWorkPolicy.APPEND_OR_REPLACE, request.build()).result.get(5, TimeUnit.SECONDS)
        }
        fun schedule(context: Context) {
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(RETRY, ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<SmsProcessingWorker>(15, TimeUnit.MINUTES).build())
            // Called on the platform thread: do not wait for WorkManager's database.
            WorkManager.getInstance(context).enqueueUniqueWork(WORK, ExistingWorkPolicy.APPEND_OR_REPLACE,
                OneTimeWorkRequestBuilder<SmsProcessingWorker>().build())
        }
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK)
            WorkManager.getInstance(context).cancelUniqueWork(RETRY)
        }
    }
}
