package jp.wojak.blepoc

import android.content.Context
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors

const val TAG = "BlePoc"

/** 128 ビットの独自 UUID (この検証だけで使う。ServiceData の鍵) */
val SERVICE_UUID: UUID = UUID.fromString("6a3f9c21-7d4b-4e58-9b1a-2c8e5f0d7a44")

/** manufacturer data の会社 ID。0xFFFF は SIG のテスト用 (出荷品には使えない) */
const val MFR_ID = 0xFFFF

/** manufacturer data の先頭の印 (ほかの 0xFFFF の広告と区別する)。'W' 'J' */
val MFR_MARK = byteArrayOf(0x57, 0x4A)

const val NEARBY_SERVICE_ID = "jp.wojak.blepoc"

/** 一覧からメモリで消すまでの時間 */
const val KEEP_MS = 3 * 60 * 1000L

enum class Method { BLE, NEARBY }
enum class Payload { SERVICE_DATA, MANUFACTURER }
enum class ScanMode(val value: Int) { LOW_POWER(0), BALANCED(1), LOW_LATENCY(2) }
enum class AdvMode(val value: Int) { LOW_POWER(0), BALANCED(1), LOW_LATENCY(2) }
enum class TxPower(val value: Int) { ULTRA_LOW(0), LOW(1), MEDIUM(2), HIGH(3) }

data class Settings(
    val method: Method = Method.BLE,
    val tx: Boolean = false,
    val rx: Boolean = false,
    val bgScan: ScanMode = ScanMode.BALANCED,
    val fgScan: ScanMode = ScanMode.LOW_LATENCY,
    val advMode: AdvMode = AdvMode.BALANCED,
    val txPower: TxPower = TxPower.MEDIUM,
    val payload: Payload = Payload.SERVICE_DATA,
    val rotateMin: Int = 5,
    val label: String = "dev",
) {
    fun save(ctx: Context) {
        ctx.getSharedPreferences("settings", Context.MODE_PRIVATE).edit()
            .putString("method", method.name).putBoolean("tx", tx).putBoolean("rx", rx)
            .putString("bgScan", bgScan.name).putString("fgScan", fgScan.name)
            .putString("advMode", advMode.name).putString("txPower", txPower.name)
            .putString("payload", payload.name).putInt("rotateMin", rotateMin)
            .putString("label", label).apply()
    }

    companion object {
        fun load(ctx: Context): Settings {
            val p = ctx.getSharedPreferences("settings", Context.MODE_PRIVATE)
            val d = Settings()
            fun <T : Enum<T>> e(key: String, def: T, values: Array<T>): T =
                values.firstOrNull { it.name == p.getString(key, null) } ?: def
            return Settings(
                method = e("method", d.method, Method.entries.toTypedArray()),
                tx = p.getBoolean("tx", d.tx),
                rx = p.getBoolean("rx", d.rx),
                bgScan = e("bgScan", d.bgScan, ScanMode.entries.toTypedArray()),
                fgScan = e("fgScan", d.fgScan, ScanMode.entries.toTypedArray()),
                advMode = e("advMode", d.advMode, AdvMode.entries.toTypedArray()),
                txPower = e("txPower", d.txPower, TxPower.entries.toTypedArray()),
                payload = e("payload", d.payload, Payload.entries.toTypedArray()),
                rotateMin = p.getInt("rotateMin", d.rotateMin),
                label = p.getString("label", d.label) ?: d.label,
            )
        }
    }
}

/** 受け取った ID 1 つ分。Nearby は RSSI が無いので null */
data class Seen(
    val idHex: String,
    val method: String,
    val rssi: Int?,
    val lastSeenMs: Long,
    /** Nearby で onEndpointLost がまだ来ていない */
    val present: Boolean = false,
)

/**
 * 画面とサービスで共有する状態 (同じプロセス)。どちらも main スレッドから触る。
 * 画面は Compose の state をそのまま読む。
 */
object Hub {
    val seen = mutableStateMapOf<String, Seen>()
    val txStatus = mutableStateOf("停止")
    val rxStatus = mutableStateOf("停止")
    val myId = mutableStateOf("")
    val serviceRunning = mutableStateOf(false)

    /** 画面が前面 (onResume から onPause まで) */
    var uiForeground = false
        private set
    /** 画面を開いた時刻 (wall clock) と、その後の最初の受信までの秒数 */
    val uiOpenedAt = mutableStateOf(0L)
    val firstRxSec = mutableStateOf<Double?>(null)
    private var uiOpenedElapsed = 0L

    /** 前面・裏が変わった時にサービスが受ける */
    var onUiForegroundChanged: (() -> Unit)? = null

    fun setUiForeground(fg: Boolean) {
        if (uiForeground == fg) return
        uiForeground = fg
        if (fg) {
            uiOpenedAt.value = System.currentTimeMillis()
            uiOpenedElapsed = SystemClock.elapsedRealtime()
            firstRxSec.value = null
        }
        CsvLog.log(if (fg) "ui_open" else "ui_close")
        onUiForegroundChanged?.invoke()
    }

    /** 受信の 1 件。一覧の更新と、画面を開いた後の最初の受信の秒数 */
    fun onReceived(idHex: String, method: String, rssi: Int?, present: Boolean = false): Double? {
        val now = System.currentTimeMillis()
        seen[idHex] = Seen(idHex, method, rssi, now, present)
        if (uiForeground && firstRxSec.value == null && uiOpenedElapsed > 0) {
            val sec = (SystemClock.elapsedRealtime() - uiOpenedElapsed) / 1000.0
            firstRxSec.value = sec
            return sec
        }
        return null
    }

    fun onLost(idHex: String) {
        seen[idHex]?.let { seen[idHex] = it.copy(present = false, lastSeenMs = System.currentTimeMillis()) }
    }

    /** 3 分を過ぎたものをメモリから消す (Nearby で見えている間は消さない) */
    fun prune() {
        val now = System.currentTimeMillis()
        seen.entries.filter { !it.value.present && now - it.value.lastSeenMs > KEEP_MS }
            .map { it.key }.forEach { seen.remove(it) }
    }
}

/**
 * CSV のログ。1 日 1 ファイル、アプリ専用の外部の場所 (adb pull で取れる)。
 * 書き込みは 1 本のスレッドで、行ごとに flush (プロセスが殺されても直前まで残す)。
 */
object CsvLog {
    const val HEADER =
        "time_ms,iso,event,method,rx_id,rssi,label,screen_on,app_fg,rx_mode,tx_id,addr,detail"

    private val exec = Executors.newSingleThreadExecutor()
    private lateinit var app: Context
    private var writer: FileWriter? = null
    private var fileDay = ""
    @Volatile var label = "dev"
    @Volatile var rxMode = ""
    @Volatile var txId = ""

    fun init(ctx: Context) {
        if (!::app.isInitialized) app = ctx.applicationContext
    }

    fun dir(): File = File(app.getExternalFilesDir(null), "logs").apply { mkdirs() }

    private fun screenOn(): Boolean =
        (app.getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive

    fun log(event: String, method: String = "", rxId: String = "", rssi: Int? = null,
            addr: String = "", detail: String = "") {
        val t = System.currentTimeMillis()
        val line = listOf(
            t.toString(), iso(t), event, method, rxId, rssi?.toString() ?: "", label,
            if (screenOn()) "1" else "0", if (Hub.uiForeground) "1" else "0",
            rxMode, txId, addr, detail,
        ).joinToString(",") { csv(it) }
        if (event != "rx") Log.i(TAG, line)
        exec.execute { write(t, line) }
    }

    private fun write(t: Long, line: String) {
        try {
            val day = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date(t))
            if (writer == null || day != fileDay) {
                writer?.close()
                val f = File(dir(), "blepoc_$day.csv")
                val isNew = !f.exists() || f.length() == 0L
                writer = FileWriter(f, true).also { if (isNew) it.write(HEADER + "\n") }
                fileDay = day
            }
            writer!!.write(line + "\n")
            writer!!.flush()
        } catch (e: Exception) {
            Log.e(TAG, "csv write failed", e)
        }
    }

    private fun iso(t: Long) = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US).format(Date(t))

    private fun csv(s: String) =
        if (s.any { it == ',' || it == '"' || it == '\n' }) "\"" + s.replace("\"", "\"\"") + "\"" else s
}

fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }
