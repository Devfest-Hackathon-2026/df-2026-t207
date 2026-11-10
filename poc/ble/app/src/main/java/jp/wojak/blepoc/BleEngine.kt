package jp.wojak.blepoc

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

/**
 * 素の BLE。接続しない広告 (ServiceData か manufacturer data に 12 バイトの ID) と、フィルタ付きのスキャン。
 * 呼び出しはすべて main スレッド。
 */
@SuppressLint("MissingPermission") // 許可は画面で取ってからサービスを始める
class BleEngine(private val ctx: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val adapter get() = (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private val parcelUuid = ParcelUuid(SERVICE_UUID)

    // ---- 発信 ----
    private var advCallback: AdvertiseCallback? = null

    fun startAdvertising(id: ByteArray, s: Settings) {
        stopAdvertising("restart")
        val adv = adapter?.bluetoothLeAdvertiser
        if (adv == null) {
            CsvLog.log("tx_fail", "ble", detail = "no_advertiser(bt_off?)")
            Hub.txStatus.value = "失敗: advertiser が無い (Bluetooth が off?)"
            return
        }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(s.advMode.value)
            .setTxPowerLevel(s.txPower.value)
            .setConnectable(false)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .apply {
                when (s.payload) {
                    Payload.SERVICE_DATA -> addServiceData(parcelUuid, id)
                    Payload.MANUFACTURER -> addManufacturerData(MFR_ID, MFR_MARK + id)
                }
            }
            .build()
        val detail = "payload=${s.payload} adv=${s.advMode} tx=${s.txPower}"
        val cb = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                CsvLog.log("tx_start", "ble", detail = "$detail txPowerInEffect=${settingsInEffect.txPowerLevel}")
                Hub.txStatus.value = "発信中 (BLE ${s.payload}, ${s.advMode}, ${s.txPower})"
            }

            override fun onStartFailure(errorCode: Int) {
                CsvLog.log("tx_fail", "ble", detail = "${advError(errorCode)} $detail")
                Hub.txStatus.value = "失敗: ${advError(errorCode)}"
                if (advCallback === this) advCallback = null
            }
        }
        advCallback = cb
        try {
            adv.startAdvertising(settings, data, cb)
        } catch (e: Exception) {
            advCallback = null
            CsvLog.log("tx_fail", "ble", detail = "exception ${e.javaClass.simpleName}: ${e.message}")
            Hub.txStatus.value = "失敗: ${e.message}"
        }
    }

    fun stopAdvertising(reason: String) {
        val cb = advCallback ?: return
        advCallback = null
        try {
            adapter?.bluetoothLeAdvertiser?.stopAdvertising(cb)
        } catch (e: Exception) {
            CsvLog.log("tx_fail", "ble", detail = "stop_exception ${e.message}")
        }
        CsvLog.log("tx_stop", "ble", detail = reason)
        Hub.txStatus.value = "停止"
    }

    // ---- 受信 ----
    private var scanCallback: ScanCallback? = null
    private var currentMode: ScanMode? = null
    private val scanStarts = ArrayDeque<Long>() // elapsedRealtime
    private var pendingStart: Runnable? = null
    private val rearm = Runnable { startScan(currentMode ?: ScanMode.BALANCED, "rearm_9.5min", force = true) }

    /**
     * スキャンを張る (張り直す)。同じモードなら何もしない (force の時を除く)。
     * 30 秒に 5 回の制限に当たらないよう、直近 30 秒に 4 回張っていたら後にずらす。
     */
    fun startScan(mode: ScanMode, reason: String, force: Boolean = false) {
        if (!force && scanCallback != null && currentMode == mode && pendingStart == null) return
        pendingStart?.let { main.removeCallbacks(it) }
        pendingStart = null
        val now = SystemClock.elapsedRealtime()
        while (scanStarts.isNotEmpty() && now - scanStarts.first() > 30_000) scanStarts.removeFirst()
        if (scanStarts.size >= 4) {
            val wait = 30_000 - (now - scanStarts.first()) + 200
            CsvLog.log("rx_deferred", "ble", detail = "quota wait=${wait}ms mode=$mode reason=$reason")
            val r = Runnable { pendingStart = null; startScan(mode, "$reason(deferred)", force = true) }
            pendingStart = r
            currentMode = mode
            main.postDelayed(r, wait)
            return
        }
        stopScanInternal()
        val scanner = adapter?.bluetoothLeScanner
        if (scanner == null) {
            CsvLog.log("rx_fail", "ble", detail = "no_scanner(bt_off?)")
            Hub.rxStatus.value = "失敗: scanner が無い (Bluetooth が off?)"
            return
        }
        // 送り手の形の設定に関わらず受けられるよう、2 つの形のどちらでも当たるフィルタにする (OR)。
        // ServiceData のフィルタは null でなく空の配列 (null だと照合で NullPointerException)
        val filters = listOf(
            ScanFilter.Builder().setServiceData(parcelUuid, ByteArray(0)).build(),
            ScanFilter.Builder().setManufacturerData(MFR_ID, MFR_MARK, byteArrayOf(-1, -1)).build(),
        )
        val settings = ScanSettings.Builder()
            .setScanMode(mode.value)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) = handle(result)
            override fun onBatchScanResults(results: MutableList<ScanResult>) = results.forEach { handle(it) }
            override fun onScanFailed(errorCode: Int) {
                CsvLog.log("rx_fail", "ble", detail = "${scanError(errorCode)} mode=$mode")
                Hub.rxStatus.value = "失敗: ${scanError(errorCode)}"
                if (scanCallback === this) scanCallback = null
            }
        }
        try {
            scanner.startScan(filters, settings, cb)
            scanCallback = cb
            currentMode = mode
            scanStarts.addLast(now)
            CsvLog.rxMode = mode.name
            CsvLog.log("rx_start", "ble", detail = "mode=$mode reason=$reason")
            Hub.rxStatus.value = "受信中 (BLE $mode)"
            // 10 分を過ぎるとフィルタ付きでも LOW_POWER に落とされるので、9.5 分ごとに張り直す
            main.removeCallbacks(rearm)
            main.postDelayed(rearm, 570_000)
        } catch (e: Exception) {
            CsvLog.log("rx_fail", "ble", detail = "exception ${e.javaClass.simpleName}: ${e.message}")
            Hub.rxStatus.value = "失敗: ${e.message}"
        }
    }

    private fun handle(r: ScanResult) {
        val rec = r.scanRecord ?: return
        var id: ByteArray? = null
        var fmt = ""
        rec.getServiceData(parcelUuid)?.let { if (it.size >= 12) { id = it.copyOf(12); fmt = "sd" } }
        if (id == null) {
            rec.getManufacturerSpecificData(MFR_ID)?.let {
                if (it.size >= 14 && it[0] == MFR_MARK[0] && it[1] == MFR_MARK[1]) {
                    id = it.copyOfRange(2, 14); fmt = "mfr"
                }
            }
        }
        val idHex = id?.hex() ?: return
        val addr = try { r.device.address } catch (_: Exception) { "" }
        val first = Hub.onReceived(idHex, "ble", r.rssi)
        CsvLog.log("rx", "ble", idHex, r.rssi, addr, fmt)
        if (first != null) CsvLog.log("first_rx", "ble", idHex, r.rssi, addr, "sec=%.3f".format(first))
    }

    private fun stopScanInternal() {
        val cb = scanCallback ?: return
        scanCallback = null
        try {
            adapter?.bluetoothLeScanner?.stopScan(cb)
        } catch (e: Exception) {
            CsvLog.log("rx_fail", "ble", detail = "stop_exception ${e.message}")
        }
    }

    fun stopScan(reason: String) {
        pendingStart?.let { main.removeCallbacks(it) }
        pendingStart = null
        main.removeCallbacks(rearm)
        val had = scanCallback != null
        stopScanInternal()
        currentMode = null
        if (had) CsvLog.log("rx_stop", "ble", detail = reason)
        CsvLog.rxMode = ""
        Hub.rxStatus.value = "停止"
    }

    companion object {
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
