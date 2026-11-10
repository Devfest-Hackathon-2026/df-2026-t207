package jp.dfhack26.app.ble

import android.os.Handler
import android.os.Looper

/**
 * 常駐サービスと Flutter の窓口 (MainActivity) が共有する状態。
 * プロセスの中にだけあり、端末の外には出さない。
 */
object BleHub {
    val sightings = SightingStore()

    @Volatile var running = false
        private set
    @Volatile var transmitting = false
        private set
    @Volatile var receiving = false
        private set
    @Volatile var error: String? = null
        private set

    /** 画面 (Flutter) が前に出ているか。前ならスキャンを速くする */
    @Volatile var uiForeground = false

    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableSetOf<(Map<String, Any?>) -> Unit>()

    fun update(
        running: Boolean = this.running,
        transmitting: Boolean = this.transmitting,
        receiving: Boolean = this.receiving,
        error: String? = this.error,
    ) {
        this.running = running
        this.transmitting = transmitting
        this.receiving = receiving
        this.error = error
        val s = status()
        main.post { listeners.toList().forEach { it(s) } }
    }

    /** 状態。匿名 ID そのものは画面に要らないので含めない */
    fun status(): Map<String, Any?> = mapOf(
        "running" to running,
        "transmitting" to transmitting,
        "receiving" to receiving,
        "error" to error,
    )

    fun addListener(l: (Map<String, Any?>) -> Unit) = main.post { listeners.add(l) }
    fun removeListener(l: (Map<String, Any?>) -> Unit) = main.post { listeners.remove(l) }

    /** 画面の切り替えをサービスに伝える (サービスが登録する) */
    @Volatile var onUiForegroundChanged: (() -> Unit)? = null
}
