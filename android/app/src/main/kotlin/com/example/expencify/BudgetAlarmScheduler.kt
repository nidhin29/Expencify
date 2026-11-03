package com.example.expencify

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.*
import dev.fluttercommunity.workmanager.BackgroundWorker
import java.util.Calendar
import java.util.concurrent.Executors

/** Clock metadata only. Budget amounts stay in the encrypted database and are
 * calculated by the existing Dart dispatcher when the alarm wakes its worker. */
object BudgetAlarmScheduler {
    const val TASK = "spendy.budget.updates"
    private const val PREFS = "spendy_budget_alarms"
    private val kinds = listOf("morning", "evening", "weekly")
    private val executor = Executors.newSingleThreadExecutor()

    fun configure(context: Context, values: Map<String, Any?>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        for (kind in kinds) {
            val enabled = values[kind] as? Boolean ?: false
            val minute = (values["${kind}Minute"] as? Number)?.toInt() ?: 0
            require(minute in 0..1439)
            editor.putBoolean(kind, enabled).putInt("${kind}Minute", minute)
        }
        check(editor.commit()) { "Could not persist spending update times" }
        rearm(context)
    }

    fun rearm(context: Context) { kinds.forEach { schedule(context, it) } }

    private fun alarmIntent(context: Context, kind: String, due: Long = 0): PendingIntent =
        PendingIntent.getBroadcast(context, 7200 + kinds.indexOf(kind),
            Intent(context, BudgetAlarmReceiver::class.java).setAction("$TASK.$kind")
                .putExtra("kind", kind).putExtra("due", due),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun schedule(context: Context, kind: String) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(kind, false)) { alarms.cancel(alarmIntent(context, kind)); return }
        val minute = prefs.getInt("${kind}Minute", 0)
        val now = System.currentTimeMillis()
        val due = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, minute / 60); set(Calendar.MINUTE, minute % 60)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now) add(Calendar.DAY_OF_YEAR, 1)
            if (kind == "weekly") while (get(Calendar.DAY_OF_WEEK) != Calendar.MONDAY) add(Calendar.DAY_OF_YEAR, 1)
        }.timeInMillis
        val intent = alarmIntent(context, kind, due)
        // Exact access is optional. Never drop the alarm when access is denied.
        if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) {
            try { alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, intent); return }
            catch (_: SecurityException) { /* Permission may change concurrently. */ }
        }
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, intent)
    }

    fun dispatch(context: Context, intent: Intent, finish: () -> Unit) {
        val kind = intent.getStringExtra("kind")
        if (kind != null && kind !in kinds) { finish(); return }
        // Rearm before executing Dart, so an interrupted delivery cannot break
        // tomorrow's schedule. Boot/time changes also restore all future alarms.
        try { rearm(context) } catch (error: Exception) { Log.e("SpendyBudgetAlarm", "Rearm failed", error) }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (kind != null && !prefs.getBoolean(kind, false)) {
            finish(); return
        }
        executor.execute {
            try {
                val work = OneTimeWorkRequestBuilder<BackgroundWorker>()
                    .setInputData(workDataOf(BackgroundWorker.DART_TASK_KEY to
                        if (kind == null) "spendy.notifications.recovery" else TASK))
                    .addTag("$TASK.alarm")
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, java.util.concurrent.TimeUnit.SECONDS)
                // Android 12+ expedited jobs can execute during Doze. Older
                // Android versions retain ordinary durable job recovery.
                if (Build.VERSION.SDK_INT >= 31) work.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                val occurrence = intent.getLongExtra("due", System.currentTimeMillis())
                WorkManager.getInstance(context).enqueueUniqueWork(
                    "$TASK.alarm.${kind ?: "recovery"}.$occurrence", ExistingWorkPolicy.KEEP, work.build()
                ).result.get(8, java.util.concurrent.TimeUnit.SECONDS)
                Log.i("SpendyBudgetAlarm", "Enqueued ${kind ?: "recovery"} update")
            } catch (error: Exception) { Log.e("SpendyBudgetAlarm", "Enqueue failed", error) }
            finally { finish() }
        }
    }
}

class BudgetAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        BudgetAlarmScheduler.dispatch(context.applicationContext, intent) { pending.finish() }
    }
}
