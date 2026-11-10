package jp.dfhack26.app

import android.content.Intent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import jp.dfhack26.app.ble.BleChannel
import jp.dfhack26.app.ble.BleHub

class MainActivity : FlutterActivity() {
    private var ble: BleChannel? = null
    private var outfitNotifications: OutfitNotificationChannel? = null
    private var viewerSecurity: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ble = BleChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        outfitNotifications = OutfitNotificationChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        viewerSecurity = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jp.dfhack26.app/viewer_security")
        viewerSecurity?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                "disable" -> window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            result.success(null)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ble?.dispose()
        ble = null
        outfitNotifications?.dispose()
        outfitNotifications = null
        viewerSecurity?.setMethodCallHandler(null)
        viewerSecurity = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // 画面が前にある間は受信を速くする (すれ違ってからアプリを開いた時に早く出すため)
    override fun onResume() {
        super.onResume()
        BleHub.uiForeground = true
        BleHub.onUiForegroundChanged?.invoke()
    }

    override fun onPause() {
        BleHub.uiForeground = false
        BleHub.onUiForegroundChanged?.invoke()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        ble?.onPermissionsResult(requestCode)
        outfitNotifications?.onPermissionsResult(requestCode)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        outfitNotifications?.onNewIntent(intent)
    }
}
