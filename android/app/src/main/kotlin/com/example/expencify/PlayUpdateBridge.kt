package com.example.expencify

import androidx.activity.OnBackPressedCallback
import android.content.Intent
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** A remembered target survives cancellation, process death and loss of connectivity. */
class PlayUpdateBridge(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val manager = AppUpdateManagerFactory.create(activity)
    private val prefs = activity.getSharedPreferences("mandatory_play_update", 0)
    private val channel = MethodChannel(messenger, "com.nidhi.expencify/play_update")
    private val launcher = activity.registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { channel.invokeMethod("flowFinished", null) }

    @Suppress("DEPRECATION")
    private fun installed(): Long = activity.packageManager
        .getPackageInfo(activity.packageName, 0).let {
            if (android.os.Build.VERSION.SDK_INT >= 28) it.longVersionCode else it.versionCode.toLong()
        }

    private val backGuard = object : OnBackPressedCallback(false) {
        override fun handleOnBackPressed() {}
    }

    init {
        activity.onBackPressedDispatcher.addCallback(activity, backGuard)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "check", "start" -> {
                    backGuard.isEnabled = true
                    val current = installed()
                    if (prefs.getLong("target", 0) <= current) prefs.edit().remove("target").commit()
                    manager.appUpdateInfo.addOnSuccessListener { info ->
                        val availability = info.updateAvailability()
                        val available = availability == UpdateAvailability.UPDATE_AVAILABLE ||
                            availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                        if (available && info.availableVersionCode().toLong() > current) {
                            prefs.edit().putLong("target", maxOf(prefs.getLong("target", 0), info.availableVersionCode().toLong())).commit()
                        }
                        val required = prefs.getLong("target", 0) > current
                        backGuard.isEnabled = required
                        if (call.method == "start" && required) {
                            try {
                                if (available && info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                                    val started = manager.startUpdateFlowForResult(info, launcher,
                                        AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build())
                                    if (!started) openStore()
                                } else openStore()
                                result.success(mapOf("required" to true, "inProgress" to false))
                            } catch (_: Exception) { result.error("UPDATE_START", "Could not open the update. Please retry.", null) }
                        } else result.success(mapOf("required" to required,
                            "inProgress" to (availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS)))
                    }.addOnFailureListener {
                        // Unknown availability permits offline use only before an update has been detected.
                        val required = prefs.getLong("target", 0) > current
                        backGuard.isEnabled = required
                        result.success(mapOf("required" to required, "inProgress" to false))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun protectBack() {
        // Register after Flutter so a required update consumes back first.
        backGuard.remove()
        activity.onBackPressedDispatcher.addCallback(activity, backGuard)
    }

    private fun openStore() {
        try { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=${activity.packageName}"))) }
        catch (_: Exception) { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=${activity.packageName}"))) }
    }
}
