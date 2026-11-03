package com.example.expencify

import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class BackupCryptoBridge(messenger: BinaryMessenger) {
    companion object { private val executor = Executors.newSingleThreadExecutor() }
    init {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(messenger, "com.nidhi.expencify/backup_crypto").setMethodCallHandler { call, result ->
            if (call.method != "encrypt" && call.method != "decrypt") {
                result.notImplemented(); return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < 26) {
                result.error("UNSUPPORTED", "Native backup crypto is unavailable.", null); return@setMethodCallHandler
            }
            val data = call.argument<ByteArray>("bytes")
            val password = call.argument<String>("password")
            if (data == null || password == null || data.size > 50 * 1024 * 1024 + 1024) {
                result.error("INVALID_INPUT", "Invalid backup input.", null); return@setMethodCallHandler
            }
            executor.execute {
                try {
                    val output = if (call.method == "encrypt") BackupCrypto.encrypt(data, password) else BackupCrypto.decrypt(data, password)
                    main.post { result.success(output) }
                } catch (_: Exception) {
                    // Never include the passphrase, plaintext, path or exception message.
                    main.post { result.error("CRYPTO_FAILED", "The backup could not be processed.", null) }
                } finally { data.fill(0) }
            }
        }
    }
}
