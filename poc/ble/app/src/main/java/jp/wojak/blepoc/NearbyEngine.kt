package jp.wojak.blepoc

import android.content.Context
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Strategy

/**
 * Nearby Connections を「発見だけ」に使う。endpointInfo に 12 バイトの ID を入れる。
 * requestConnection は呼ばない。相手から接続を求められても断る。
 */
class NearbyEngine(ctx: Context) {
    private val client = Nearby.getConnectionsClient(ctx)
    private var advertising = false
    private var discovering = false
    /** 始めた回の番号。成功の知らせが止めた後に届いた時に、古い回を見分ける */
    private var advGen = 0
    private var discGen = 0
    /** endpointId → ID の hex (onEndpointLost で ID を引くため) */
    private val endpoints = mutableMapOf<String, String>()

    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            CsvLog.log("nearby_conn_rejected", "nearby", detail = "endpoint=$endpointId")
            client.rejectConnection(endpointId)
        }
        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {}
        override fun onDisconnected(endpointId: String) {}
    }

    private val discovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            val raw = info.endpointInfo
            val idHex = if (raw.size == 12) raw.hex() else return
            endpoints[endpointId] = idHex
            val first = Hub.onReceived(idHex, "nearby", null, present = true)
            CsvLog.log("rx", "nearby", idHex, addr = endpointId, detail = "found")
            if (first != null) CsvLog.log("first_rx", "nearby", idHex, addr = endpointId, detail = "sec=%.3f".format(first))
        }

        override fun onEndpointLost(endpointId: String) {
            val idHex = endpoints.remove(endpointId) ?: return
            Hub.onLost(idHex)
            CsvLog.log("rx_lost", "nearby", idHex, addr = endpointId)
        }
    }

    fun startAdvertising(id: ByteArray) {
        stopAdvertising("restart")
        val opts = AdvertisingOptions.Builder().setStrategy(Strategy.P2P_CLUSTER).build()
        advertising = true
        val gen = ++advGen
        client.startAdvertising(id, NEARBY_SERVICE_ID, lifecycle, opts)
            .addOnSuccessListener {
                if (gen != advGen || !advertising) return@addOnSuccessListener
                CsvLog.log("tx_start", "nearby", detail = "P2P_CLUSTER")
                Hub.txStatus.value = "発信中 (Nearby P2P_CLUSTER)"
            }
            .addOnFailureListener { e ->
                if (gen != advGen) return@addOnFailureListener
                advertising = false
                CsvLog.log("tx_fail", "nearby", detail = err(e))
                Hub.txStatus.value = "失敗: ${err(e)}"
            }
    }

    fun stopAdvertising(reason: String) {
        if (!advertising) return
        advertising = false
        advGen++
        client.stopAdvertising()
        CsvLog.log("tx_stop", "nearby", detail = reason)
        Hub.txStatus.value = "停止"
    }

    fun startDiscovery() {
        if (discovering) return
        val opts = DiscoveryOptions.Builder().setStrategy(Strategy.P2P_CLUSTER).build()
        discovering = true
        val gen = ++discGen
        CsvLog.rxMode = "nearby"
        client.startDiscovery(NEARBY_SERVICE_ID, discovery, opts)
            .addOnSuccessListener {
                if (gen != discGen || !discovering) return@addOnSuccessListener
                CsvLog.log("rx_start", "nearby", detail = "P2P_CLUSTER")
                Hub.rxStatus.value = "受信中 (Nearby P2P_CLUSTER)"
            }
            .addOnFailureListener { e ->
                if (gen != discGen) return@addOnFailureListener
                discovering = false
                CsvLog.log("rx_fail", "nearby", detail = err(e))
                Hub.rxStatus.value = "失敗: ${err(e)}"
            }
    }

    fun stopDiscovery(reason: String) {
        if (!discovering) return
        discovering = false
        discGen++
        client.stopDiscovery()
        endpoints.values.forEach { Hub.onLost(it) }
        endpoints.clear()
        CsvLog.log("rx_stop", "nearby", detail = reason)
        CsvLog.rxMode = ""
        Hub.rxStatus.value = "停止"
    }

    private fun err(e: Exception): String {
        val code = (e as? ApiException)?.statusCode
        return if (code != null) "${ConnectionsStatusCodes.getStatusCodeString(code)}($code)"
        else "${e.javaClass.simpleName}: ${e.message}"
    }
}
