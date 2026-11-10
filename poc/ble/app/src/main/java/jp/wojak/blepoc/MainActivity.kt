package jp.wojak.blepoc

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    /** 許可の状態が変わった時に画面を描き直すための数 */
    private val permTick = mutableIntStateOf(0)
    private val message = mutableStateOf("")
    private val formVersion = mutableIntStateOf(0)

    private val permLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        permTick.intValue++
        CsvLog.log("perm_result", detail = it.entries.joinToString(" ") { e -> "${e.key.substringAfterLast('.')}=${e.value}" })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CsvLog.init(this)
        val s = Settings.load(this)
        CsvLog.label = s.label
        val caps = PocService.capsString(this)
        Log.i(TAG, "caps $caps")
        CsvLog.log("caps", detail = caps)
        // 回転などで作り直された時は extra を当て直さない
        val fromAdb = if (savedInstanceState == null) adbSettings(intent, s) else null
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    // adb から設定が来たら、画面の設定の欄を保存した設定で作り直す
                    key(formVersion.intValue) {
                        Screen(if (formVersion.intValue == 0) fromAdb ?: s else Settings.load(this@MainActivity), caps)
                    }
                }
            }
        }
        fromAdb?.let { applySettings(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        adbSettings(intent, Settings.load(this))?.let {
            applySettings(it)
            formVersion.intValue++
        }
    }

    /**
     * adb から設定を当てる (画面に触らずに条件を切り替えるため。電池の試験など)。
     * 例: adb shell am start -n jp.wojak.blepoc/.MainActivity --ez tx true --ez rx false --es method BLE
     * 付けられる extra: method, tx, rx, bgScan, fgScan, advMode, txPower, payload (文字列は enum の名前), rotateMin (int), label
     */
    private fun adbSettings(i: Intent?, base: Settings): Settings? {
        val e = i?.extras ?: return null
        val keys = setOf("method", "tx", "rx", "bgScan", "fgScan", "advMode", "txPower", "payload", "rotateMin", "label")
        if (e.keySet().none { it in keys }) return null
        fun <T : Enum<T>> en(k: String, def: T, values: Array<T>): T =
            e.getString(k)?.let { v -> values.firstOrNull { it.name.equals(v, true) } } ?: def
        val s = base.copy(
            method = en("method", base.method, Method.entries.toTypedArray()),
            tx = e.getBoolean("tx", base.tx),
            rx = e.getBoolean("rx", base.rx),
            bgScan = en("bgScan", base.bgScan, ScanMode.entries.toTypedArray()),
            fgScan = en("fgScan", base.fgScan, ScanMode.entries.toTypedArray()),
            advMode = en("advMode", base.advMode, AdvMode.entries.toTypedArray()),
            txPower = en("txPower", base.txPower, TxPower.entries.toTypedArray()),
            payload = en("payload", base.payload, Payload.entries.toTypedArray()),
            rotateMin = e.getInt("rotateMin", base.rotateMin).coerceAtLeast(1),
            label = e.getString("label")?.replace(",", "")?.trim() ?: base.label,
        )
        CsvLog.log("adb_settings", detail = s.toString().replace(",", ";"))
        return s
    }

    override fun onResume() {
        super.onResume()
        permTick.intValue++
        Hub.setUiForeground(true)
    }

    override fun onPause() {
        Hub.setUiForeground(false)
        super.onPause()
    }

    // ---- 許可 ----
    private fun wanted(): List<String> = buildList {
        add(Manifest.permission.BLUETOOTH_SCAN)
        add(Manifest.permission.BLUETOOTH_ADVERTISE)
        add(Manifest.permission.BLUETOOTH_CONNECT)
        if (Build.VERSION.SDK_INT >= 33) {
            add(Manifest.permission.POST_NOTIFICATIONS)
            add(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            // Nearby Connections は Android 12 (API 31/32) では位置の許可が要る
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }

    private fun granted(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
    private fun missing() = wanted().filterNot { granted(it) }

    private fun locationOn(): Boolean =
        (getSystemService(LOCATION_SERVICE) as LocationManager).isLocationEnabled

    private fun btOn(): Boolean =
        (getSystemService(BLUETOOTH_SERVICE) as BluetoothManager).adapter?.isEnabled == true

    // ---- サービス ----
    private fun applySettings(s: Settings) {
        s.save(this)
        CsvLog.label = s.label
        if (!s.tx && !s.rx) {
            if (Hub.serviceRunning.value) stopService(Intent(this, PocService::class.java))
            message.value = "発信も受信も OFF なので常駐を止めた"
            return
        }
        val bt = listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT).filterNot { granted(it) }
        if (bt.isNotEmpty()) {
            message.value = "付近のデバイスの許可が要る。許可を求める"
            permLauncher.launch(missing().toTypedArray())
            return
        }
        if (!btOn()) {
            message.value = "Bluetooth が OFF。設定で ON にしてから適用する"
            return
        }
        if (s.method == Method.NEARBY && Build.VERSION.SDK_INT <= 32 && !locationOn()) {
            message.value = "注意: 位置情報が OFF。Nearby はこの版の Android では位置情報が ON でないと動かない"
        } else message.value = ""
        startForegroundService(Intent(this, PocService::class.java).setAction(PocService.ACTION_APPLY))
    }

    private fun stopAll() {
        stopService(Intent(this, PocService::class.java))
    }

    // ---- 画面 ----
    @Composable
    private fun Screen(initial: Settings, caps: String) {
        var s by remember { mutableStateOf(initial) }
        var saved by remember { mutableStateOf(initial) }
        var rotateText by remember { mutableStateOf(initial.rotateMin.toString()) }
        var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
        LaunchedEffect(Unit) {
            while (true) {
                now = System.currentTimeMillis(); Hub.prune(); delay(1000)
            }
        }
        @Suppress("UNUSED_VARIABLE") val tick = permTick.intValue

        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text("すれ違い検証", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text("常駐: ${if (Hub.serviceRunning.value) "動作中" else "停止"}")
            Text("発信: ${Hub.txStatus.value}")
            Text("受信: ${Hub.rxStatus.value}")
            Text("自分の ID: ${Hub.myId.value.take(8).ifEmpty { "-" }}", fontFamily = FontFamily.Monospace)
            if (message.value.isNotEmpty()) Text(message.value, color = MaterialTheme.colorScheme.error)

            Section("画面を開いてから最初の受信")
            Text(Hub.firstRxSec.value?.let { "%.2f 秒".format(it) }
                ?: if (s.rx || saved.rx) "待っている" else "受信が OFF", fontSize = 20.sp)

            Section("直近 3 分に受け取った ID")
            val list = Hub.seen.values.sortedByDescending { it.lastSeenMs }
            if (list.isEmpty()) Text("まだ無い")
            list.forEach {
                val ago = if (it.present) "見えている" else "${(now - it.lastSeenMs) / 1000} 秒前"
                Text("${it.idHex.take(8)}  ${it.method}  ${it.rssi?.let { r -> "$r dBm" } ?: "-"}  $ago",
                    fontFamily = FontFamily.Monospace)
            }

            Section("設定")
            OutlinedTextField(s.label, { s = s.copy(label = it.replace(",", "").trim()) },
                label = { Text("端末の名前 (ログの区別用)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Chips("方式", Method.entries, s.method) { s = s.copy(method = it) }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("発信"); Switch(s.tx, { s = s.copy(tx = it) })
                Spacer(Modifier.width(24.dp))
                Text("受信"); Switch(s.rx, { s = s.copy(rx = it) })
            }
            OutlinedTextField(rotateText, {
                rotateText = it.filter(Char::isDigit).take(3)
                rotateText.toIntOrNull()?.takeIf { v -> v >= 1 }?.let { v -> s = s.copy(rotateMin = v) }
            }, label = { Text("ID の切り替えの間隔 (分)") }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))

            Text("BLE の受信", fontWeight = FontWeight.Bold)
            Chips("常駐中", ScanMode.entries, s.bgScan) { s = s.copy(bgScan = it) }
            Chips("画面を開いている時", ScanMode.entries, s.fgScan) { s = s.copy(fgScan = it) }
            Text("BLE の発信", fontWeight = FontWeight.Bold)
            Chips("広告のモード", AdvMode.entries, s.advMode) { s = s.copy(advMode = it) }
            Chips("送信の強さ", TxPower.entries, s.txPower) { s = s.copy(txPower = it) }
            Chips("載せ方", Payload.entries, s.payload) { s = s.copy(payload = it) }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button({ saved = s; applySettings(s) }) { Text("適用 (始める / 当て直す)") }
                OutlinedButton({ s = s.copy(tx = false, rx = false); saved = s; s.save(this@MainActivity); stopAll() }) { Text("全部止める") }
            }
            if (s != saved) Text("まだ適用していない変更がある", color = MaterialTheme.colorScheme.error)

            Section("許可")
            wanted().forEach { Text("${if (granted(it)) "OK" else "未"}  ${it.substringAfterLast('.')}", fontFamily = FontFamily.Monospace) }
            if (Build.VERSION.SDK_INT <= 32) Text("位置情報 (Nearby に要る): ${if (locationOn()) "ON" else "OFF"}")
            Text("Bluetooth: ${if (btOn()) "ON" else "OFF"}")
            if (missing().isNotEmpty()) Button({ permLauncher.launch(missing().toTypedArray()) }) { Text("足りない許可を求める") }

            Section("端末の対応")
            caps.split(" ").forEach { Text(it, fontFamily = FontFamily.Monospace) }

            Section("ログ")
            Text(CsvLog.dir().absolutePath, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
            Spacer(Modifier.height(24.dp))
        }
    }

    @Composable
    private fun Section(title: String) {
        Spacer(Modifier.height(8.dp))
        HorizontalDivider()
        Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
    }

    @Composable
    private fun <T : Enum<T>> Chips(title: String, values: List<T>, selected: T, onSelect: (T) -> Unit) {
        Text(title, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            values.forEach { v ->
                FilterChip(selected = v == selected, onClick = { onSelect(v) },
                    label = { Text(v.name, fontSize = 11.sp) })
            }
        }
    }
}
