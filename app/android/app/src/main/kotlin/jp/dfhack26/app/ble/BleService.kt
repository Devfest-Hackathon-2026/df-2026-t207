package jp.dfhack26.app.ble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import jp.dfhack26.app.MainActivity

/**
 * 常駐 (foreground service、connectedDevice 型)。公開している間、ポケットの中でも
 * 匿名 ID の発信と、近くの人の ID の受信を続ける。
 *
 * - 発信する ID は、サーバから受け取った並び ([BroadcastSchedule]) から「今の時刻の枠の物」を選ぶ
 * - 公開が切れる時刻 (その日の 24 時) に自分で止まる
 * - OS に止められても戻れるよう、設定は端末の中 (SharedPreferences) に置き、START_STICKY にする
 */
class BleService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private lateinit var radio: BleRadio
    private var schedule: BroadcastSchedule? = null
    private var transmit = false
    private var receive = false

    private val tick = Runnable { applyNow() }

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)) {
                BluetoothAdapter.STATE_ON -> applyNow(restartScan = true)
                BluetoothAdapter.STATE_OFF -> {
                    radio.stopAdvertising()
                    radio.stopScan()
                    BleHub.update(error = "bluetooth_off")
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        radio = BleRadio(this)
        createChannel()
        registerReceiver(bluetoothReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
        BleHub.onUiForegroundChanged = { main.post { if (receive) radio.scan(scanMode()) } }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            startForeground(NOTIF_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } catch (e: Exception) {
            // 許可が無い時など。Flutter 側に伝えて止まる
            Log.w(BleRadio.TAG, "startForeground failed ${e.javaClass.simpleName}")
            BleHub.update(running = false, error = "start_failed")
            stopSelf()
            return START_NOT_STICKY
        }
        when (intent?.action) {
            ACTION_STOP -> {
                stopAll()
                clearSaved(this)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                schedule = intent.getStringExtra(EXTRA_SCHEDULE)?.let(BroadcastSchedule::fromJson)
                transmit = intent.getBooleanExtra(EXTRA_TRANSMIT, true)
                receive = intent.getBooleanExtra(EXTRA_RECEIVE, true)
                save()
            }
            else -> if (!load()) { // OS が戻した時。設定が無ければ止まる
                stopSelf()
                return START_NOT_STICKY
            }
        }
        BleHub.update(running = true, error = null)
        applyNow(restartScan = true)
        return START_STICKY
    }

    /** 今の時刻で、発信する ID と受信を当て直し、次に替える時刻を予約する */
    private fun applyNow(restartScan: Boolean = false) {
        main.removeCallbacks(tick)
        val now = System.currentTimeMillis()
        val s = schedule
        if (s != null && now >= s.untilMs) { // 24 時を過ぎた
            stopAll()
            clearSaved(this)
            stopSelf()
            return
        }
        if (transmit && s != null) {
            val id = s.idAt(now)
            if (id != null) radio.advertise(id) else radio.stopAdvertising()
        }
        if (receive) radio.scan(scanMode(), force = restartScan)
        s?.nextChangeAfter(now)?.let { main.postDelayed(tick, (it - now + 500).coerceAtLeast(1_000)) }
    }

    private fun scanMode() =
        if (BleHub.uiForeground) BleRadio.ScanMode.LOW_LATENCY else BleRadio.ScanMode.BALANCED

    private fun stopAll() {
        main.removeCallbacks(tick)
        radio.stopAdvertising()
        radio.stopScan()
        BleHub.sightings.clear()
        BleHub.update(running = false, transmitting = false, receiving = false)
    }

    override fun onDestroy() {
        stopAll()
        try { unregisterReceiver(bluetoothReceiver) } catch (_: Exception) {}
        BleHub.onUiForegroundChanged = null
        super.onDestroy()
    }

    private fun save() {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString("schedule", schedule?.toJson())
            .putBoolean("transmit", transmit)
            .putBoolean("receive", receive)
            .apply()
    }

    private fun load(): Boolean {
        val p = getSharedPreferences(PREFS, MODE_PRIVATE)
        val json = p.getString("schedule", null) ?: return false
        schedule = BroadcastSchedule.fromJson(json)
        transmit = p.getBoolean("transmit", true)
        receive = p.getBoolean("receive", true)
        return true
    }

    private fun createChannel() {
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "近くへの公開", NotificationManager.IMPORTANCE_LOW).apply {
                description = "公開している間に出る通知"
            },
        )
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("近くに公開中")
            .setContentText("ポケットに入れたままで大丈夫です。今日の 24 時に自動で終わります")
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }

    companion object {
        const val ACTION_START = "jp.dfhack26.app.ble.START"
        const val ACTION_STOP = "jp.dfhack26.app.ble.STOP"
        const val EXTRA_SCHEDULE = "schedule"
        const val EXTRA_TRANSMIT = "transmit"
        const val EXTRA_RECEIVE = "receive"
        private const val CHANNEL = "publishing"
        private const val NOTIF_ID = 26
        private const val PREFS = "ble_service"

        fun clearSaved(ctx: Context) {
            ctx.getSharedPreferences(PREFS, MODE_PRIVATE).edit().clear().apply()
        }
    }
}
