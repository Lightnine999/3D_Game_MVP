package com.zombieescape.payments

import android.app.Activity
import android.content.Intent
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class TossGamePayments(godot: Godot) : GodotPlugin(godot) {
    companion object {
        private const val REQUEST_CODE = 8029
    }

    @Volatile private var pendingOrderId: String? = null
    @Volatile private var pendingAmount: Int = 0

    override fun getPluginName(): String = "TossGamePayments"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo(
            "payment_result",
            String::class.java,
            String::class.java,
            String::class.java,
            Int::class.javaObjectType,
        )
    )

    @UsedByGodot
    fun open_test_widget(
        clientKey: String,
        customerKey: String,
        orderId: String,
        orderName: String,
        amount: Int,
    ): Boolean {
        val host = activity ?: return false
        if (pendingOrderId != null || !TestOrderPolicy.isValid(clientKey, customerKey, orderId, orderName, amount)) {
            return false
        }
        pendingOrderId = orderId
        pendingAmount = amount
        val intent = Intent(host, TossPaymentActivity::class.java)
            .putExtra(TossPaymentActivity.KEY_CLIENT, clientKey)
            .putExtra(TossPaymentActivity.KEY_CUSTOMER, customerKey)
            .putExtra(TossPaymentActivity.KEY_ORDER, orderId)
            .putExtra(TossPaymentActivity.KEY_NAME, orderName)
            .putExtra(TossPaymentActivity.KEY_AMOUNT, amount)
        runOnUiThread { host.startActivityForResult(intent, REQUEST_CODE) }
        return true
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onMainActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE) return
        val expectedOrder = pendingOrderId ?: return
        val expectedAmount = pendingAmount
        pendingOrderId = null
        pendingAmount = 0
        val returnedOrder = data?.getStringExtra(TossPaymentActivity.KEY_ORDER).orEmpty()
        val returnedAmount = data?.getIntExtra(TossPaymentActivity.KEY_AMOUNT, 0) ?: 0
        val paymentKey = data?.getStringExtra(TossPaymentActivity.KEY_PAYMENT).orEmpty()
        val authorized = resultCode == Activity.RESULT_OK &&
            data?.getStringExtra(TossPaymentActivity.KEY_STATUS) == "authorized" &&
            returnedOrder == expectedOrder && returnedAmount == expectedAmount && paymentKey.isNotBlank()
        val status = if (authorized) "authorized" else if (data?.getStringExtra(TossPaymentActivity.KEY_STATUS) == "cancelled") "cancelled" else "payment_failed"
        // The payment key is only passed to Godot for immediate server confirmation, never logged.
        emitSignal("payment_result", status, if (authorized) paymentKey else "", expectedOrder, expectedAmount)
    }
}
