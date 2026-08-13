package com.rastin.rastin_time_tracker

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import java.nio.charset.StandardCharsets
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val trackingIntentAction =
            "com.rastin.rastin_time_tracker.TRACKING_ACTION"
        private var activeMethodChannel: MethodChannel? = null

        fun dispatchTrackingAction(action: String): Boolean {
            val channel = activeMethodChannel ?: return false
            channel.invokeMethod("trackingNotificationAction", action)
            return true
        }
    }

    private val channelName = "rtt/window"
    private val pickAudioRequest = 9017
    private val saveCsvRequest = 9018
    private val notificationPermissionRequest = 9019
    private val trackingNotificationId = 1001
    private val breakReminderNotificationId = 1002
    private val trackingChannelId = "rtt_tracking"
    private val breakReminderChannelId = "rtt_break_reminder"
    private var pendingAudioPick: MethodChannel.Result? = null
    private var pendingCsvSave: MethodChannel.Result? = null
    private var pendingCsvContent: String? = null
    private var methodChannel: MethodChannel? = null
    private var pendingTrackingAction: String? = null
    private var reminderPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )
        activeMethodChannel = methodChannel
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "chooseReminderSoundFile" -> chooseReminderSoundFile(result)
                "playReminderSound" -> {
                    playReminderSound(call.argument<String>("path"))
                    result.success(null)
                }
                "stopReminderSound" -> {
                    stopReminderSound()
                    result.success(null)
                }
                "saveCsvFile" -> saveCsvFile(
                    call.argument<String>("fileName"),
                    call.argument<String>("content"),
                    result
                )
                "showTrackingNotification" -> {
                    showTrackingNotification(
                        call.argument<String>("title") ?: "RTT",
                        call.argument<String>("text") ?: "Tracking",
                        call.argument<Boolean>("paused") ?: false
                    )
                    result.success(null)
                }
                "cancelTrackingNotification" -> {
                    cancelTrackingNotification()
                    result.success(null)
                }
                "showBreakReminderNotification" -> {
                    showBreakReminderNotification()
                    result.success(null)
                }
                "cancelBreakReminderNotification" -> {
                    cancelBreakReminderNotification()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        pendingTrackingAction?.let {
            methodChannel?.invokeMethod("trackingNotificationAction", it)
            pendingTrackingAction = null
        }
        handleTrackingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleTrackingIntent(intent)
    }

    override fun onDestroy() {
        if (activeMethodChannel == methodChannel) activeMethodChannel = null
        super.onDestroy()
    }

    private fun chooseReminderSoundFile(result: MethodChannel.Result) {
        if (pendingAudioPick != null) {
            result.error("busy", "A sound picker is already open.", null)
            return
        }
        pendingAudioPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, pickAudioRequest)
    }

    private fun saveCsvFile(
        fileName: String?,
        content: String?,
        result: MethodChannel.Result
    ) {
        if (pendingCsvSave != null) {
            result.error("busy", "A CSV save dialog is already open.", null)
            return
        }
        if (fileName.isNullOrBlank() || content == null) {
            result.error("invalid-arguments", "CSV file name and content are required.", null)
            return
        }
        pendingCsvSave = result
        pendingCsvContent = content
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/csv"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        startActivityForResult(intent, saveCsvRequest)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == saveCsvRequest) {
            finishCsvSave(resultCode, data)
            return
        }
        if (requestCode != pickAudioRequest) return
        val result = pendingAudioPick ?: return
        pendingAudioPick = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: SecurityException) {
            // Some providers grant one-time access only. The URI can still work
            // for the current session, so keep it.
        }
        result.success(uri.toString())
    }

    private fun showTrackingNotification(
        title: String,
        text: String,
        paused: Boolean
    ) {
        if (!ensureNotificationPermission()) return
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                trackingChannelId,
                "Tracking timer",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows the active Rastin Time Tracker timer."
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, trackingChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val pauseAction = if (paused) "resume_tracking" else "pause_tracking"
        val pauseTitle = if (paused) "Resume" else "Pause"
        builder
            .setSmallIcon(R.drawable.ic_stat_rtt)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openAppPendingIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_STATUS)
            .setPriority(Notification.PRIORITY_LOW)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(
                        this,
                        if (paused) {
                            android.R.drawable.ic_media_play
                        } else {
                            android.R.drawable.ic_media_pause
                        }
                    ),
                    pauseTitle,
                    backgroundTrackingActionPendingIntent(pauseAction, 2101)
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(
                        this,
                        android.R.drawable.ic_media_ff
                    ),
                    "Stop",
                    foregroundTrackingActionPendingIntent("stop_tracking", 2102)
                ).build()
            )
        manager.notify(trackingNotificationId, builder.build())
    }

    private fun showBreakReminderNotification() {
        if (!ensureNotificationPermission()) return
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                breakReminderChannelId,
                "Break reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows break reminders while tracking."
            }
            manager.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, breakReminderChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_rtt)
            .setContentTitle("RTT")
            .setContentText("Wanna take a break?")
            .setContentIntent(openAppPendingIntent())
            .setAutoCancel(true)
            .setShowWhen(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setPriority(Notification.PRIORITY_HIGH)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_media_pause),
                    "Pause",
                    backgroundTrackingActionPendingIntent("break_pause", 2201)
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
                    "Continue",
                    backgroundTrackingActionPendingIntent("break_continue", 2202)
                ).build()
            )
        manager.notify(breakReminderNotificationId, builder.build())
    }

    private fun cancelTrackingNotification() {
        getSystemService(NotificationManager::class.java)
            .cancel(trackingNotificationId)
    }

    private fun cancelBreakReminderNotification() {
        getSystemService(NotificationManager::class.java)
            .cancel(breakReminderNotificationId)
    }

    private fun ensureNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        if (
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return true
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequest
        )
        return false
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            2100,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun backgroundTrackingActionPendingIntent(
        action: String,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(this, TrackingActionReceiver::class.java).apply {
            putExtra("tracking_action", action)
        }
        return PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun foregroundTrackingActionPendingIntent(
        action: String,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            this.action = trackingIntentAction
            putExtra("tracking_action", action)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun handleTrackingIntent(intent: Intent?): Boolean {
        if (intent?.action != trackingIntentAction) return false
        val action = intent.getStringExtra("tracking_action") ?: return false
        val channel = methodChannel
        if (channel == null) {
            pendingTrackingAction = action
        } else {
            channel.invokeMethod("trackingNotificationAction", action)
        }
        return true
    }

    private fun finishCsvSave(resultCode: Int, data: Intent?) {
        val result = pendingCsvSave ?: return
        val content = pendingCsvContent
        pendingCsvSave = null
        pendingCsvContent = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null || content == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.openOutputStream(uri)?.use { output ->
                output.write(content.toByteArray(StandardCharsets.UTF_8))
            } ?: run {
                result.error("csv-save", "Could not open the selected file.", null)
                return
            }
            result.success(uri.toString())
        } catch (_: Exception) {
            result.error("csv-save", "Could not save the CSV file.", null)
        }
    }

    private fun playReminderSound(path: String?) {
        stopReminderSound()
        try {
            reminderPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                if (path.isNullOrBlank()) {
                    assets.openFd("breaktime.mp3").use { asset ->
                        setDataSource(
                            asset.fileDescriptor,
                            asset.startOffset,
                            asset.length
                        )
                    }
                } else {
                    setDataSource(this@MainActivity, Uri.parse(path))
                }
                isLooping = false
                prepare()
                start()
            }
        } catch (_: Exception) {
            stopReminderSound()
        }
    }

    private fun stopReminderSound() {
        reminderPlayer?.run {
            try {
                if (isPlaying) stop()
            } catch (_: Exception) {
            }
            release()
        }
        reminderPlayer = null
    }
}
