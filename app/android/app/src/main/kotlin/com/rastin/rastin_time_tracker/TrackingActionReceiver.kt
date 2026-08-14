package com.rastin.rastin_time_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TrackingActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.getStringExtra("tracking_action") ?: return
        if (action == MainActivity.breakAlarmAction) {
            MainActivity.showBreakReminderNotification(context)
            MainActivity.dispatchTrackingAction("show_break_reminder")
            MainActivity.scheduleNextStoredBreakReminderAlarm(context)
            return
        }
        if (action == "break_continue") {
            MainActivity.cancelBreakReminderNotification(context)
            MainActivity.scheduleNextStoredBreakReminderAlarm(context)
        }
        if (MainActivity.dispatchTrackingAction(action)) return
        val activityIntent = Intent(context, MainActivity::class.java).apply {
            this.action = MainActivity.trackingIntentAction
            putExtra("tracking_action", action)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_NO_USER_ACTION)
            addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
        }
        context.startActivity(activityIntent)
    }
}
