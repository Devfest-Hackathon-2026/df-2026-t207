package jp.wojak.blepoc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.ServiceCompat
import java.security.SecureRandom

/**
 * 常駐 (foreground service、connectedDevice 型)。発信・受信・ID の切り替えをここで持つ。
 * START_NOT_STICKY: OS に殺されたら勝手に戻さない (戻すと「止まったか」の試験が見えなくなる)。
 */
class PocService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private lateinit var ble: BleEngine
    private lateinit var nearby: NearbyEngine
    private var settings = Settings()
    private var myId = ByteArray(12)
    private var rotateDueElapsed = 0L
    private val random = SecureRandom()

    private val rotate = object : Runnable {
        override fun run() {
            val late = SystemClock.elapsedRealtime() - rotateDueElapsed
            newId("timer late_ms=$late")
            startTx()
            scheduleRotate()
        }
    }

    private val heartbeat = object : Runnable {
        override fun run() {
            Hub.prune()
            CsvLog.log("hb", settings.method.name.lowercase(), detail = "tx=${settings.tx} rx=${settings.rx} seen=${Hub.seen.size}")
            main.postDelayed(this, 60_000)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            CsvLog.log(if (i.action == Intent.ACTION_SCREEN_ON) "screen_on" else "screen_off")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        CsvLog.init(this)
        ble = BleEngine(this)
        nearby = NearbyEngine(this)
        createChannel()
        registerReceiver(screenReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_SCREEN_OFF)
        })
        Hub.onUiForegroundChanged = { onUiChanged() }
        Hub.serviceRunning.value = true
        CsvLog.log("svc_create", detail = capsString(this))
        main.postDelayed(heartbeat, 60_000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            ServiceCompat.startForeground(this, NOTIF_ID, notification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } catch (e: Exception) {
            CsvLog.log("svc_fail", detail = "startForeground ${e.javaClass.simpleName}: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_STOP) {
            stopAll("user_stop")
            stopSelf()
            return START_NOT_STICKY
        }
        apply(Settings.load(this))
        return START_NOT_STICKY
    }

    /** 設定を当て直す。いったん全部止めて、新しい ID で始め直す */
    private fun apply(s: Settings) {
        stopAll("apply")
        settings = s
        CsvLog.label = s.label
        CsvLog.log("apply", s.method.name.lowercase(), detail = s.toString().replace(",", ";"))
        if (s.tx) {
            newId("apply")
            startTx()
            scheduleRotate()
        }
        if (s.rx) startRx("apply")
        if (!s.tx && !s.rx) stopSelf()
        else getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification())
    }

    private fun newId(reason: String) {
        random.nextBytes(myId)
        val hex = myId.hex()
        CsvLog.txId = hex
        Hub.myId.value = hex
        CsvLog.log("id_rotate", settings.method.name.lowercase(), detail = reason)
    }

    private fun startTx() {
        when (settings.method) {
            Method.BLE -> ble.startAdvertising(myId.copyOf(), settings)
            Method.NEARBY -> nearby.startAdvertising(myId.copyOf())
        }
    }

    private fun scheduleRotate() {
        main.removeCallbacks(rotate)
        val ms = settings.rotateMin.coerceAtLeast(1) * 60_000L
        rotateDueElapsed = SystemClock.elapsedRealtime() + ms
        main.postDelayed(rotate, ms)
    }

    private fun startRx(reason: String) {
        when (settings.method) {
            Method.BLE -> ble.startScan(currentScanMode(), reason, force = true)
            Method.NEARBY -> nearby.startDiscovery()
        }
    }

    private fun currentScanMode() = if (Hub.uiForeground) settings.fgScan else settings.bgScan

    /** 画面を開いた時はスキャンを張り直す (本番の「開いてからスキャン」と同じ測り方にする)。閉じた時は常駐のモードへ */
    private fun onUiChanged() {
        if (!settings.rx) return
        when (settings.method) {
            Method.BLE ->
                if (Hub.uiForeground) ble.startScan(settings.fgScan, "ui_open", force = true)
                else ble.startScan(settings.bgScan, "ui_close")
            // Nearby は探索のモードが 1 つなので、開いた時に探索を始め直すだけ (見えていた相手も見つけ直す)
            Method.NEARBY -> if (Hub.uiForeground) {
                nearby.stopDiscovery("ui_open")
                nearby.startDiscovery()
            }
        }
    }

    private fun stopAll(reason: String) {
        main.removeCallbacks(rotate)
        ble.stopAdvertising(reason)
        ble.stopScan(reason)
        nearby.stopAdvertising(reason)
        nearby.stopDiscovery(reason)
        CsvLog.txId = ""
        Hub.myId.value = ""
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        CsvLog.log("task_removed")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopAll("svc_destroy")
        main.removeCallbacks(heartbeat)
        try { unregisterReceiver(screenReceiver) } catch (_: Exception) {}
        Hub.onUiForegroundChanged = null
        Hub.serviceRunning.value = false
        CsvLog.log("svc_destroy")
        super.onDestroy()
    }

    private fun createChannel() {
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "すれ違い検証の常駐", NotificationManager.IMPORTANCE_LOW))
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val what = listOfNotNull(if (settings.tx) "発信" else null, if (settings.rx) "受信" else null)
            .joinToString("・").ifEmpty { "準備中" }
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_poc)
            .setContentTitle("すれ違い検証: $what (${settings.method})")
            .setContentText("ラベル ${settings.label}")
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }

    companion object {
        const val ACTION_APPLY = "jp.wojak.blepoc.APPLY"
        const val ACTION_STOP = "jp.wojak.blepoc.STOP"
        private const val CHANNEL = "poc"
        private const val NOTIF_ID = 1

        fun capsString(ctx: Context): String {
            val a = (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
                ?: return "no_adapter"
            fun q(f: () -> Any): String = try { f().toString() } catch (e: Exception) { "err:${e.javaClass.simpleName}" }
            return "multiAdv=${q { a.isMultipleAdvertisementSupported }} " +
                "extAdv=${q { a.isLeExtendedAdvertisingSupported }} " +
                "maxAdvLen=${q { a.leMaximumAdvertisingDataLength }} " +
                "btOn=${q { a.isEnabled }} sdk=${android.os.Build.VERSION.SDK_INT} model=${android.os.Build.MODEL}"
        }
    }
}
