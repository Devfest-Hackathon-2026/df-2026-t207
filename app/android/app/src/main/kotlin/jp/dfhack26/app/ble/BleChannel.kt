package jp.dfhack26.app.ble

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter (lib/ble/ble_controller.dart) との窓口。
 * - MethodChannel `jp.dfhack26.app/ble`: 許可、常駐の開始と停止、受け取った ID の一覧
 * - EventChannel `jp.dfhack26.app/ble/status`: 常駐の状態が変わるたびに送る
 */
class BleChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val method = MethodChannel(messenger, "jp.dfhack26.app/ble")
    private val events = EventChannel(messenger, "jp.dfhack26.app/ble/status")
    private var pendingPermission: MethodChannel.Result? = null
    private var statusListener: ((Map<String, Any?>) -> Unit)? = null

    init {
        method.setMethodCallHandler(this)
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                val l: (Map<String, Any?>) -> Unit = { sink.success(it) }
                statusListener = l
                BleHub.addListener(l)
                sink.success(BleHub.status())
            }

            override fun onCancel(arguments: Any?) {
                statusListener?.let { BleHub.removeListener(it) }
                statusListener = null
            }
        })
    }

    fun dispose() {
        method.setMethodCallHandler(null)
        events.setStreamHandler(null)
        statusListener?.let { BleHub.removeListener(it) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(capabilities())
            "permissions" -> result.success(permissionState())
            "requestPermissions" -> requestPermissions(result)
            "start" -> start(call, result)
            "stop" -> {
                activity.startService(Intent(activity, BleService::class.java).setAction(BleService.ACTION_STOP))
                result.success(null)
            }
            "status" -> result.success(BleHub.status())
            "sightings" -> {
                val windowMs = (call.argument<Number>("windowMs") ?: SightingStore.DEFAULT_KEEP_MS).toLong()
                result.success(
                    BleHub.sightings.recent(System.currentTimeMillis(), windowMs).map {
                        mapOf(
                            "id" to it.idHex,
                            "lastSeenMs" to it.lastSeenMs,
                            "rssi" to it.rssiMax,
                            "txPower" to it.txPowerDbm,
                        )
                    },
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun capabilities(): Map<String, Any?> {
        val adapter = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?)?.adapter
        return mapOf(
            "supported" to (adapter != null &&
                activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)),
            "bluetoothOn" to (adapter?.isEnabled == true),
        )
    }

    private val bluetoothPermissions = arrayOf(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_ADVERTISE,
    )

    private fun granted(p: String) =
        activity.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun permissionState(): Map<String, Boolean> = mapOf(
        "bluetooth" to bluetoothPermissions.all(::granted),
        "notification" to (Build.VERSION.SDK_INT < 33 || granted(Manifest.permission.POST_NOTIFICATIONS)),
    )

    private fun requestPermissions(result: MethodChannel.Result) {
        if (pendingPermission != null) {
            result.error("busy", "許可を求めている途中です", null)
            return
        }
        val wanted = buildList {
            addAll(bluetoothPermissions)
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }.filterNot(::granted)
        if (wanted.isEmpty()) {
            result.success(permissionState())
            return
        }
        pendingPermission = result
        activity.requestPermissions(wanted.toTypedArray(), REQUEST_CODE)
    }

    /** MainActivity の onRequestPermissionsResult から呼ぶ */
    fun onPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pendingPermission?.success(permissionState())
        pendingPermission = null
        return true
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        if (!bluetoothPermissions.all(::granted)) {
            result.error("permission", "Bluetooth の許可がありません", null)
            return
        }
        val slots = call.argument<List<Map<String, Any?>>>("slots") ?: emptyList()
        val until = call.argument<Number>("untilMs")?.toLong()
        if (until == null) {
            result.error("bad_args", "untilMs がありません", null)
            return
        }
        val schedule = try {
            BroadcastSchedule.fromChannel(slots, until)
        } catch (e: Exception) {
            result.error("bad_args", "slots の形が違います", null)
            return
        }
        val intent = Intent(activity, BleService::class.java)
            .setAction(BleService.ACTION_START)
            .putExtra(BleService.EXTRA_SCHEDULE, schedule.toJson())
            .putExtra(BleService.EXTRA_TRANSMIT, call.argument<Boolean>("transmit") ?: true)
            .putExtra(BleService.EXTRA_RECEIVE, call.argument<Boolean>("receive") ?: true)
        try {
            activity.startForegroundService(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("start_failed", e.javaClass.simpleName, null)
        }
    }

    companion object {
        private const val REQUEST_CODE = 2601
    }
}
