package jp.dfhack26.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class OutfitNotificationChannel(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "jp.dfhack26.app/outfit_notifications")
    private val preferences = activity.getSharedPreferences("outfit_notifications", 0)
    private val manager = activity.getSystemService(NotificationManager::class.java)
    private var openedJob: String? = jobFrom(activity.intent)
    private var permissionRequest: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            val uid = call.argument<String>("uid")
            val job = call.argument<String>("job")
            when (call.method) {
                "permission" -> requestPermission(result)
                "takeOpenJob" -> {
                    val opened = openedJob
                    openedJob = null
                    activity.intent?.removeExtra("job")
                    result.success(opened)
                }
                "pendingJob" -> result.success(uid?.let { preferences.getString("pending:$it", null) })
                "remember" -> {
                    if (uid != null && job != null) {
                        preferences.getString("pending:$uid", null)?.let { manager.cancel(it, NOTIFICATION_ID) }
                        preferences.edit().putString("pending:$uid", job).remove("notified:$uid").apply()
                    }
                    result.success(null)
                }
                "forget" -> {
                    if (uid != null && job != null && preferences.getString("pending:$uid", null) == job) {
                        preferences.edit().remove("pending:$uid").remove("notified:$uid").apply()
                        manager.cancel(job, NOTIFICATION_ID)
                    }
                    result.success(null)
                }
                "cancel" -> {
                    if (job != null) manager.cancel(job, NOTIFICATION_ID)
                    result.success(null)
                }
                "complete" -> {
                    if (uid != null && job != null) show(uid, job)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onNewIntent(intent: Intent) {
        openedJob = jobFrom(intent) ?: return
        channel.invokeMethod("openRequested", null)
    }

    private fun jobFrom(intent: Intent?): String? =
        intent?.takeIf { it.action == OPEN_RESULT }?.getStringExtra("job")
            ?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{8,64}")) }

    private fun hasPermission() = Build.VERSION.SDK_INT < 33 ||
        activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission() || permissionRequest != null || preferences.getBoolean("asked", false)) {
            result.success(null)
            return
        }
        preferences.edit().putBoolean("asked", true).apply()
        permissionRequest = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    fun onPermissionsResult(requestCode: Int) {
        if (requestCode != PERMISSION_REQUEST) return
        permissionRequest?.success(null)
        permissionRequest = null
    }

    private fun show(uid: String, job: String) {
        if (preferences.getString("pending:$uid", null) != job ||
            preferences.getString("notified:$uid", null) == job ||
            !hasPermission() || !manager.areNotificationsEnabled()
        ) return

        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "コーデの処理結果", NotificationManager.IMPORTANCE_DEFAULT),
        )
        if (manager.getNotificationChannel(CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE) return

        val intent = Intent(activity, MainActivity::class.java).apply {
            action = OPEN_RESULT
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("job", job)
        }
        val contentIntent = PendingIntent.getActivity(
            activity, NOTIFICATION_ID, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        manager.notify(
            job,
            NOTIFICATION_ID,
            Notification.Builder(activity, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentTitle("コーデの処理が完了しました")
                .setContentText("タップしてコーデを確認できます")
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setContentIntent(contentIntent)
                .setOnlyAlertOnce(true)
                .setAutoCancel(true)
                .build(),
        )
        preferences.edit().putString("notified:$uid", job).apply()
    }

    fun dispose() {
        permissionRequest?.success(null)
        permissionRequest = null
        channel.setMethodCallHandler(null)
    }

    private companion object {
        const val CHANNEL_ID = "outfit_results"
        const val OPEN_RESULT = "jp.dfhack26.app.OPEN_OUTFIT_RESULT"
        const val NOTIFICATION_ID = 211
        const val PERMISSION_REQUEST = 4211
    }
}
