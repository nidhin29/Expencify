package com.example.expencify

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Queue keys never leave Android Keystore. No plaintext fallback for protected data. */
object PendingSmsStore {
    private val lock = Any()
    private const val alias = "spendy_pending_sms_key_v1"
    private const val legacyKey = "flutter.pending_sms_list"
    private val magic = "SPSMS001".toByteArray(Charsets.US_ASCII)
    private fun file(context: Context) = AtomicFile(File(context.noBackupFilesDir, "pending_sms_v1.bin"))
    private fun exists(context: Context): Boolean {
        val base = file(context).baseFile
        return base.exists() || File(base.path + ".bak").exists()
    }
    private fun key(context: Context): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(alias, null)
        if (existing != null) return existing as SecretKey
        check(!exists(context)) { "Pending SMS encryption key is unavailable; queue preserved" }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setRandomizedEncryptionRequired(true).build())
        return generator.generateKey()
    }
    private fun readCipher(context: Context): JSONArray {
        if (!exists(context)) return JSONArray()
        val bytes = file(context).openRead().use { it.readBytes() }
        check(bytes.size >= 36 && bytes.copyOfRange(0, 8).contentEquals(magic)) { "Invalid protected SMS queue; file preserved" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(context), GCMParameterSpec(128, bytes.copyOfRange(8, 20)))
        cipher.updateAAD(magic)
        val plain = cipher.doFinal(bytes.copyOfRange(20, bytes.size))
        return try { JSONArray(String(plain, Charsets.UTF_8)) } finally { plain.fill(0) }
    }
    private fun writeCipher(context: Context, items: JSONArray) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(context))
        cipher.updateAAD(magic)
        val plain = items.toString().toByteArray(Charsets.UTF_8)
        val bytes = try { magic + cipher.iv + cipher.doFinal(plain) } finally { plain.fill(0) }
        val target = file(context)
        val stream = target.startWrite()
        try { stream.write(bytes); target.finishWrite(stream) }
        catch (e: Exception) { target.failWrite(stream); throw e }
    }
    private fun load(context: Context): JSONArray {
        val protected = readCipher(context)
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val legacy = prefs.getString(legacyKey, null) ?: return protected
        val old = JSONArray(legacy)
        val ids = (0 until protected.length()).map { protected.getJSONObject(it).getString("id") }.toMutableSet()
        for (i in 0 until old.length()) {
            val item = old.getJSONObject(i)
            if (!item.has("id")) {
                // Stable even if removal of old preferences fails and migration retries.
                val seed = item.optString("sender") + "\u0000" + item.getLong("timestamp") + "\u0000" + item.getString("body") + "\u0000" + i
                val digest = MessageDigest.getInstance("SHA-256").digest(seed.toByteArray(Charsets.UTF_8))
                item.put("id", "legacy:" + digest.joinToString("") { "%02x".format(it) })
            }
            if (ids.add(item.getString("id"))) protected.put(item)
        }
        writeCipher(context, protected)
        // Read/authenticate the persisted copy before removing the old one.
        check(readCipher(context).toString() == protected.toString()) { "Pending SMS migration verification failed" }
        check(prefs.edit().remove(legacyKey).commit()) { "Cannot remove legacy SMS queue; protected copy preserved" }
        return protected
    }
    fun readPending(context: Context): List<Map<String, Any>> = synchronized(lock) {
        val items = load(context)
        (0 until items.length()).map {
            val item = items.getJSONObject(it)
            mapOf("id" to item.getString("id"), "body" to item.getString("body"), "sender" to item.optString("sender"), "timestamp" to item.getLong("timestamp"))
        }
    }
    fun enqueue(context: Context, id: String, sender: String, body: String, timestamp: Long) = synchronized(lock) {
        val items = load(context)
        items.put(JSONObject().put("id", id).put("sender", sender).put("body", body).put("timestamp", timestamp))
        writeCipher(context, items)
    }
    fun ack(context: Context, id: String) = synchronized(lock) {
        val items = load(context)
        val remaining = JSONArray()
        for (i in 0 until items.length()) {
            val item = items.getJSONObject(i)
            if (item.getString("id") != id) remaining.put(item)
        }
        writeCipher(context, remaining)
    }
    fun clear(context: Context) = synchronized(lock) {
        check(context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().remove(legacyKey).commit()) { "Cannot clear legacy SMS queue" }
        file(context).delete()
        check(!exists(context)) { "Cannot clear protected SMS queue" }
    }
}
