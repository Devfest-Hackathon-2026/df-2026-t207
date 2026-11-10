package jp.dfhack26.app.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BlePayloadTest {
    @Test
    fun `ID 11 バイトと送信の強さ 1 バイトで 12 バイトになり、読み戻せる`() {
        val bytes = BlePayload.encode("3fa91c0e7b2d4a8c61e5f0", -7)
        assertEquals(12, bytes.size)
        val d = BlePayload.decode(bytes)!!
        assertEquals("3fa91c0e7b2d4a8c61e5f0", d.idHex)
        assertEquals(-7, d.txPowerDbm)
    }

    @Test
    fun `UUID と合わせて通常の発信の 31 バイトに入る`() {
        // AD の長さ 1 + 種類 1 + UUID 16 + 中身 12 = 30 (接続しない発信は Flags を載せない)
        assertEquals(30, 1 + 1 + 16 + BlePayload.PAYLOAD_BYTES)
    }

    @Test
    fun `短すぎる中身は読まない`() {
        assertNull(BlePayload.decode(ByteArray(11)))
        assertNull(BlePayload.decode(null))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `長さの違う ID は発信しない`() {
        BlePayload.encode("abcd", 0)
    }
}

class BroadcastScheduleTest {
    private val m = 60_000L
    private val s = BroadcastSchedule(
        slots = listOf(
            BroadcastSchedule.Slot(10 * m, "aa".repeat(11)),
            BroadcastSchedule.Slot(15 * m, "bb".repeat(11)),
            BroadcastSchedule.Slot(20 * m, "cc".repeat(11)),
        ),
        untilMs = 25 * m,
    )

    @Test
    fun `今の時刻の枠の ID を選ぶ (タイマーが遅れても枠と ID がずれない)`() {
        assertNull(s.idAt(9 * m))
        assertEquals("aa".repeat(11), s.idAt(10 * m))
        assertEquals("aa".repeat(11), s.idAt(14 * m))
        // 14 分のタイマーが 3 分遅れて 17 分に起きても、17 分の枠の ID になる
        assertEquals("bb".repeat(11), s.idAt(17 * m))
        assertEquals("cc".repeat(11), s.idAt(24 * m))
    }

    @Test
    fun `公開が切れた後は発信しない`() {
        assertNull(s.idAt(25 * m))
    }

    @Test
    fun `次に替える時刻は次の枠の始まりか、切れる時刻`() {
        assertEquals(15 * m, s.nextChangeAfter(12 * m))
        assertEquals(25 * m, s.nextChangeAfter(21 * m))
        assertNull(s.nextChangeAfter(26 * m))
    }
}

class SightingStoreTest {
    private val sec = 1_000L

    @Test
    fun `直近 5 分だけを新しい順に持ち、強さは一番強かった値`() {
        val store = SightingStore()
        store.add("aa".repeat(11), -80, -7, 0)
        store.add("bb".repeat(11), -70, -7, 60 * sec)
        store.add("aa".repeat(11), -65, -7, 120 * sec)
        store.add("aa".repeat(11), -90, -7, 130 * sec)

        val recent = store.recent(130 * sec)
        assertEquals(listOf("aa".repeat(11), "bb".repeat(11)), recent.map { it.idHex })
        assertEquals(-65, recent.first().rssiMax)

        // b は 60 秒に見たきりなので、6 分 (360 秒) を過ぎると消える
        assertEquals(listOf("aa".repeat(11)), store.recent(361 * sec).map { it.idHex })
    }
}
