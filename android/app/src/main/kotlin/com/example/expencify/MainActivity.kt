package com.example.expencify

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import android.util.Log

class MainActivity : FlutterFragmentActivity() {
    companion object { private val modelIntegrityExecutor = java.util.concurrent.Executors.newSingleThreadExecutor() }
    private var playUpdates: PlayUpdateBridge? = null
    private var liteRtLm: LiteRtLmBridge? = null
    private val CHANNEL = "com.example.expencify/asset_delivery"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        val enabled = getSharedPreferences("spendy_screen_privacy", MODE_PRIVATE)
            .getBoolean("enabled", false) ||
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getBoolean("flutter.app_lock_enabled", false)
        if (enabled) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nidhi.expencify/app_lock")
            .setMethodCallHandler { call, result ->
                if (call.method != "configure") { result.notImplemented(); return@setMethodCallHandler }
                val enabled = call.argument<Boolean>("enabled") == true
                if (enabled) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                getSharedPreferences("spendy_screen_privacy", MODE_PRIVATE).edit()
                    .putBoolean("enabled", enabled).apply()
                result.success(null)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nidhi.expencify/budget_alarms")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "configure" -> { BudgetAlarmScheduler.configure(applicationContext,
                            call.arguments as? Map<String, Any?> ?: emptyMap()); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) { result.error("BUDGET_ALARM", "Could not schedule spending updates.", null) }
            }
        // Keep only the isolated benchmark visible during a timed device run.
        // The normal application never changes screen-awake behavior here.
        if (packageName == "com.nidhi.expencify.modelcheck") {
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        liteRtLm = LiteRtLmBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nidhi.expencify/model_integrity").setMethodCallHandler { call, result ->
            if (call.method != "sha256File") { result.notImplemented(); return@setMethodCallHandler }
            val path = call.argument<String>("path")
            if (path == null) { result.error("INVALID_MODEL", "Invalid model file.", null); return@setMethodCallHandler }
            modelIntegrityExecutor.execute {
                try {
                    val file = java.io.File(path).canonicalFile
                    val privateRoot = java.io.File(applicationInfo.dataDir).canonicalPath + java.io.File.separator
                    require(file.path.startsWith(privateRoot) && file.isFile)
                    val digest = java.security.MessageDigest.getInstance("SHA-256")
                    file.inputStream().buffered(1024 * 1024).use { input ->
                        val buffer = ByteArray(1024 * 1024)
                        while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
                    }
                    val hash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
                    runOnUiThread { result.success(hash) }
                } catch (_: Exception) {
                    runOnUiThread { result.error("MODEL_HASH_FAILED", "Could not verify the model file.", null) }
                }
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nidhi.expencify/diagnostics").setMethodCallHandler { call, result ->
            when (call.method) {
                "processCpuMs" -> result.success(android.os.Process.getElapsedCpuTime())
                "androidApi" -> result.success(android.os.Build.VERSION.SDK_INT)
                "clear" -> { DiagnosticsSamples.clear(applicationContext); result.success(null) }
                else -> result.notImplemented()
            }
        }
        BackupCryptoBridge(flutterEngine.dartExecutor.binaryMessenger)
        playUpdates = PlayUpdateBridge(this, flutterEngine.dartExecutor.binaryMessenger)

        // Cache the engine so background receivers can reuse it if the app is open
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.expencify/native_sms").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "scheduleSmsWork" -> { SmsProcessingWorker.schedule(applicationContext); result.success(null) }
                    "cancelSmsWork" -> { SmsProcessingWorker.cancel(applicationContext); result.success(null) }
                    "getApplicationId" -> result.success(applicationContext.packageName)
                    "securePendingSms" -> result.success(PendingSmsStore.readPending(applicationContext).size)
                    "readPendingSms" -> result.success(SmsReceiver.readPending(applicationContext))
                    "ackPendingSms" -> { SmsReceiver.ack(applicationContext, call.argument<String>("id") ?: ""); result.success(null) }
                    "clearPendingSms" -> { SmsReceiver.clearPending(applicationContext); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("SMS_QUEUE", "The protected SMS queue could not be opened. Existing data was preserved.", null) }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getAssetPackPath") {
                val packName = call.argument<String>("packName")
                if (packName == null) {
                    result.error("INVALID_ARGUMENT", "Pack name is null", null)
                    return@setMethodCallHandler
                }
                
                val assetPackManager = AssetPackManagerFactory.getInstance(applicationContext)
                val location = assetPackManager.getPackLocation(packName)
                
                if (location != null) {
                    result.success(location.assetsPath())
                } else {
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        playUpdates?.protectBack()
    }

    override fun onDestroy() {
        liteRtLm?.dispose()
        liteRtLm = null
        Log.d("EXPENCIFY_MAIN", "MainActivity destroying — clearing main_engine from cache")
        // Clear the cache BEFORE calling super.onDestroy(), as super.onDestroy() 
        // triggers engine detachment/destruction.
        FlutterEngineCache.getInstance().remove("main_engine")
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        try {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        } catch (e: Exception) {
            Log.e("EXPENCIFY_MAIN", "onRequestPermissionsResult absorbed exception: ${e.message}")
        }
    }
}
