package jp.dfhack26.app.ble

/**
 * 受け取った匿名 ID を、端末のメモリにだけ直近 [keepMs] (既定 5 分) 持つ。
 * サーバに送るのは、アプリを開いて見る時だけ (`POST /v1/nearby`)。ファイルには書かない。
 */
class SightingStore(private val keepMs: Long = DEFAULT_KEEP_MS) {
    data class Sighting(
        val idHex: String,
        /** 最後に受け取った時刻 (エポックからのミリ秒) */
        val lastSeenMs: Long,
        /** 保持している間で一番強かった受信の強さ (dBm)。揺れが大きいので最大を使う */
        val rssiMax: Int,
        /** 発信に載っていた送信の強さ (dBm) */
        val txPowerDbm: Int,
    )

    private val map = HashMap<String, Sighting>()

    @Synchronized
    fun add(idHex: String, rssi: Int, txPowerDbm: Int, nowMs: Long) {
        val old = map[idHex]
        map[idHex] = Sighting(
            idHex = idHex,
            lastSeenMs = nowMs,
            rssiMax = if (old == null) rssi else maxOf(old.rssiMax, rssi),
            txPowerDbm = txPowerDbm,
        )
        prune(nowMs)
    }

    /** 直近 [windowMs] に受け取った物を、新しい順に */
    @Synchronized
    fun recent(nowMs: Long, windowMs: Long = keepMs): List<Sighting> {
        prune(nowMs)
        return map.values.filter { nowMs - it.lastSeenMs <= windowMs }.sortedByDescending { it.lastSeenMs }
    }

    @Synchronized
    fun clear() = map.clear()

    private fun prune(nowMs: Long) {
        map.values.removeAll { nowMs - it.lastSeenMs > keepMs }
    }

    companion object {
        const val DEFAULT_KEEP_MS = 5 * 60 * 1000L
    }
}
