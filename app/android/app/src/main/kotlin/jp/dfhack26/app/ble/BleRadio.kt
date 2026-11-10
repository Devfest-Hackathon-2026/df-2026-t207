package jp.dfhack26.app.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log

/**
 * 素の BLE の発信と受信 (poc/ble の BleEngine から、本番に要る所だけを移した)。
 * - 発信: 接続しない広告。端末名も送信電力の項目も載せない。ServiceData に 12 バイト
 * - 受信: ServiceData のフィルタ付きのスキャン。受け取った ID は [BleHub.sightings] に入れる
 * 呼び出しはすべて main スレッド。ログに匿名 ID を書かない (AGENTS.md)。
 */
@SuppressLint("MissingPermission") // 許可は Flutter の画面で取ってからサービスを始める
class BleRadio(private val ctx: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val adapter get() = (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private val uuid = ParcelUuid(BlePayload.SERVICE_UUID)

    // ---- 発信 ----
    private var advCallback: AdvertiseCallback? = null
    private var advertisingId: String? = null

    /** [idHex] で発信する。同じ ID で発信中なら何もしない (ID を替える時は止めて始め直す) */
    fun advertise(idHex: String) {
        if (advCallback != null && advertisingId == idHex) return
        stopAdvertising()
        val adv = adapter?.takeIf { it.isEnabled }?.bluetoothLeAdvertiser
        if (adv == null) {
            BleHub.update(transmitting = false, error = "bluetooth_off")
            return
        }
        val level = AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setTxPowerLevel(level)
            .setConnectable(false)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceData(uuid, BlePayload.encode(idHex, BlePayload.txPowerDbm(level)))
            .build()
        val cb = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                BleHub.update(transmitting = true, error = null)
            }

            override fun onStartFailure(errorCode: Int) {
                Log.w(TAG, "advertise failed ${advError(errorCode)}")
                if (advCallback === this) {
                    advCallback = null
                    advertisingId = null
                }
                BleHub.update(transmitting = false, error = "advertise_${advError(errorCode)}")
            }
        }
        advCallback = cb
        advertisingId = idHex
        try {
            adv.startAdvertising(settings, data, cb)
        } catch (e: Exception) {
            advCallback = null
            advertisingId = null
            Log.w(TAG, "advertise exception ${e.javaClass.simpleName}")
            BleHub.update(transmitting = false, error = "advertise_exception")
        }
    }

    fun stopAdvertising() {
        val cb = advCallback ?: return
        advCallback = null
        advertisingId = null
        try {
            adapter?.bluetoothLeAdvertiser?.stopAdvertising(cb)
        } catch (_: Exception) {
        }
        BleHub.update(transmitting = false)
    }

    // ---- 受信 ----
    enum class ScanMode(val value: Int) {
        BALANCED(ScanSettings.SCAN_MODE_BALANCED),
        LOW_LATENCY(ScanSettings.SCAN_MODE_LOW_LATENCY),
    }

    private var scanCallback: ScanCallback? = null
    private var currentMode: ScanMode? = null
    private val scanStarts = ArrayDeque<Long>() // elapsedRealtime
    private var pendingStart: Runnable? = null
    private val rearm = Runnable { scan(currentMode ?: ScanMode.BALANCED, force = true) }

    /**
     * スキャンを張る (張り直す)。同じモードなら何もしない (force の時を除く)。
     * OS の「30 秒に 5 回」の制限に当たらないよう、直近 30 秒に 4 回張っていたら後にずらす。
     */
    fun scan(mode: ScanMode, force: Boolean = false) {
        if (!force && scanCallback != null && currentMode == mode && pendingStart == null) return
        pendingStart?.let { main.removeCallbacks(it) }
        pendingStart = null
        val now = SystemClock.elapsedRealtime()
        while (scanStarts.isNotEmpty() && now - scanStarts.first() > 30_000) scanStarts.removeFirst()
        if (scanStarts.size >= 4) {
            val wait = 30_000 - (now - scanStarts.first()) + 200
            val r = Runnable { pendingStart = null; scan(mode, force = true) }
            pendingStart = r
            currentMode = mode
            main.postDelayed(r, wait)
            return
        }
        stopScanInternal()
        val scanner = adapter?.takeIf { it.isEnabled }?.bluetoothLeScanner
        if (scanner == null) {
            BleHub.update(receiving = false, error = "bluetooth_off")
            return
        }
        // ServiceData のフィルタは null でなく空の配列 (null だと照合で落ちる、poc/ble で確認済み)
        val filters = listOf(ScanFilter.Builder().setServiceData(uuid, ByteArray(0)).build())
        val settings = ScanSettings.Builder()
            .setScanMode(mode.value)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) = handle(result)
            override fun onBatchScanResults(results: MutableList<ScanResult>) = results.forEach { handle(it) }
            override fun onScanFailed(errorCode: Int) {
                Log.w(TAG, "scan failed ${scanError(errorCode)}")
                if (scanCallback === this) scanCallback = null
                BleHub.update(receiving = false, error = "scan_${scanError(errorCode)}")
            }
        }
        try {
            scanner.startScan(filters, settings, cb)
            scanCallback = cb
            currentMode = mode
            scanStarts.addLast(now)
            BleHub.update(receiving = true)
            // 10 分を過ぎるとフィルタ付きでも省電力のモードに落とされるので、9.5 分ごとに張り直す
            main.removeCallbacks(rearm)
            main.postDelayed(rearm, 570_000)
        } catch (e: Exception) {
            Log.w(TAG, "scan exception ${e.javaClass.simpleName}")
            BleHub.update(receiving = false, error = "scan_exception")
        }
    }

    private fun handle(r: ScanResult) {
        val decoded = BlePayload.decode(r.scanRecord?.getServiceData(uuid)) ?: return
        BleHub.sightings.add(decoded.idHex, r.rssi, decoded.txPowerDbm, System.currentTimeMillis())
    }

    private fun stopScanInternal() {
        val cb = scanCallback ?: return
        scanCallback = null
        try {
            adapter?.bluetoothLeScanner?.stopScan(cb)
        } catch (_: Exception) {
        }
    }

    fun stopScan() {
        pendingStart?.let { main.removeCallbacks(it) }
        pendingStart = null
        main.removeCallbacks(rearm)
        stopScanInternal()
        currentMode = null
        BleHub.update(receiving = false)
    }

    companion object {
        const val TAG = "DfHackBle"

        fun advError(c: Int) = when (c) {
            AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE -> "DATA_TOO_LARGE"
            AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "TOO_MANY_ADVERTISERS"
            AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED -> "ALREADY_STARTED"
            AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR -> "INTERNAL_ERROR"
            AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "FEATURE_UNSUPPORTED"
            else -> "code_$c"
        }

        fun scanError(c: Int) = when (c) {
            ScanCallback.SCAN_FAILED_ALREADY_STARTED -> "ALREADY_STARTED"
            ScanCallback.SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "APP_REGISTRATION_FAILED"
            ScanCallback.SCAN_FAILED_INTERNAL_ERROR -> "INTERNAL_ERROR"
            ScanCallback.SCAN_FAILED_FEATURE_UNSUPPORTED -> "FEATURE_UNSUPPORTED"
            ScanCallback.SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES -> "OUT_OF_HW_RESOURCES"
            ScanCallback.SCAN_FAILED_SCANNING_TOO_FREQUENTLY -> "SCANNING_TOO_FREQUENTLY"
            else -> "code_$c"
        }
    }
}
