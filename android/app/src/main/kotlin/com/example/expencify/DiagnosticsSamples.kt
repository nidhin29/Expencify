package com.example.expencify

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Technical job metadata only. Opt-in, bounded and independent of SMS contents. */
object DiagnosticsSamples {
    private const val enabled = "flutter.local_diagnostics_enabled"
    private const val records = "flutter.local_diagnostics_native"
    @Synchronized fun record(context: Context, wallMs: Long, cpuMs: Long, outcome: String) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (!prefs.getBoolean(enabled, false)) return
            val text = prefs.getString(records, "[]") ?: "[]"
            val old = if (text.length <= 32768) try { JSONArray(text) } catch (_: Exception) { JSONArray() } else JSONArray()
            val now = System.currentTimeMillis() / 60000 * 60000
            val recent = (0 until old.length()).mapNotNull { old.optJSONObject(it) }
                .filter { it.optLong("at_minute") >= now - 3 * 86400000L }.takeLast(59)
            val next = JSONArray()
            recent.forEach { next.put(it) }
            next.put(JSONObject().put("at_minute", now).put("wall_ms", wallMs.coerceIn(0, 600000))
                .put("process_cpu_ms", cpuMs.coerceIn(0, 600000))
                .put("outcome", if (outcome in listOf("success", "skipped", "retry")) outcome else "retry"))
            prefs.edit().putString(records, next.toString()).apply()
        } catch (_: Exception) { /* Never interferes with message processing. */ }
    }
    @Synchronized fun clear(context: Context) {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().remove(records).commit()
    }
}
