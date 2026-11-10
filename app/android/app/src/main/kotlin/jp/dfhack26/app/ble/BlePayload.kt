package jp.dfhack26.app.ble

import java.util.UUID

/**
 * 発信の中身の決まり (docs/tech-decisions.md の 1 節)。
 *
 * 128 ビットの UUID の ServiceData に「匿名 ID 11 バイト + 送信の強さ 1 バイト」の 12 バイト。
 * UUID と合わせて 30 バイトで、通常の発信の上限 31 バイトに入る (接続しない発信は Flags を載せない)。
 * Android に依存しないので、JUnit で確かめられる。
 */
object BlePayload {
    /** poc/ble と同じ UUID (2 台の検証の結果をそのまま使えるように) */
    val SERVICE_UUID: UUID = UUID.fromString("6a3f9c21-7d4b-4e58-9b1a-2c8e5f0d7a44")

    const val ID_BYTES = 11
    const val PAYLOAD_BYTES = ID_BYTES + 1

    /** AdvertiseSettings の送信の強さの段階 → おおよその dBm (Android の文書の値) */
    fun txPowerDbm(level: Int): Int = when (level) {
        0 -> -21 // ULTRA_LOW
        1 -> -15 // LOW
        2 -> -7 // MEDIUM
        else -> 1 // HIGH
    }

    fun encode(idHex: String, txPowerDbm: Int): ByteArray {
        val id = hexToBytes(idHex)
        require(id.size == ID_BYTES) { "匿名 ID は $ID_BYTES バイト (16 進で 22 文字)" }
        return id + byteArrayOf(txPowerDbm.coerceIn(-128, 127).toByte())
    }

    /** 受け取った ServiceData を読む。形が違えば null */
    fun decode(data: ByteArray?): Decoded? {
        if (data == null || data.size < PAYLOAD_BYTES) return null
        return Decoded(
            idHex = bytesToHex(data.copyOf(ID_BYTES)),
            txPowerDbm = data[ID_BYTES].toInt(), // 符号付き
        )
    }

    data class Decoded(val idHex: String, val txPowerDbm: Int)

    fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0 && hex.all { it in '0'..'9' || it in 'a'..'f' }) { "16 進の小文字だけ" }
        return ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }

    fun bytesToHex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
}
