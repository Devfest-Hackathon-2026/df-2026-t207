package jp.dfhack26.app.ble

import org.json.JSONArray
import org.json.JSONObject

/**
 * サーバ (`PUT /v1/publish`) から受け取った、その日の匿名 ID の並び。
 *
 * 端末は画面オフ (Doze) の間タイマーが数分遅れるので、「次の ID」ではなく
 * 「今の時刻の枠の ID」を毎回選ぶ (docs/tech-decisions.md の 1 節)。
 */
data class BroadcastSchedule(
    /** 枠の始まり (エポックからのミリ秒) の昇順 */
    val slots: List<Slot>,
    /** 公開が切れる時刻 (その日の 24 時)。過ぎたら止める */
    val untilMs: Long,
) {
    data class Slot(val startMs: Long, val idHex: String)

    /** 今の時刻の枠の ID。まだ始まっていないか、切れていれば null */
    fun idAt(nowMs: Long): String? {
        if (nowMs >= untilMs || slots.isEmpty()) return null
        return slots.lastOrNull { it.startMs <= nowMs }?.idHex
    }

    /** 次に ID を替える時刻。無ければ null */
    fun nextChangeAfter(nowMs: Long): Long? {
        val next = slots.firstOrNull { it.startMs > nowMs }?.startMs
        return listOfNotNull(next, untilMs.takeIf { it > nowMs }).minOrNull()
    }

    fun toJson(): String = JSONObject()
        .put("untilMs", untilMs)
        .put("slots", JSONArray().apply {
            slots.forEach { put(JSONObject().put("startMs", it.startMs).put("id", it.idHex)) }
        })
        .toString()

    companion object {
        fun fromJson(s: String): BroadcastSchedule {
            val o = JSONObject(s)
            val a = o.getJSONArray("slots")
            return BroadcastSchedule(
                slots = (0 until a.length()).map {
                    val x = a.getJSONObject(it)
                    Slot(x.getLong("startMs"), x.getString("id"))
                }.sortedBy { it.startMs },
                untilMs = o.getLong("untilMs"),
            )
        }

        /** Flutter から来た形 ([{slotStart: ms, id: hex}], until: ms) */
        fun fromChannel(slots: List<Map<String, Any?>>, untilMs: Long) = BroadcastSchedule(
            slots = slots.map { Slot((it["slotStart"] as Number).toLong(), it["id"] as String) }
                .sortedBy { it.startMs },
            untilMs = untilMs,
        )
    }
}
