package com.example.expencify

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import android.util.Log

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.expencify/asset_delivery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Cache the engine so background receivers can reuse it if the app is open
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)

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

    override fun onDestroy() {
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
