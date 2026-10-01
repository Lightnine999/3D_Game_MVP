package com.zombieescape.payments

/** UI-thread confined: claim requests/results before invoking SDK or Activity callbacks. */
internal class PaymentAttemptState {
    var inFlight = false
        private set
    var terminal = false
        private set

    fun canPay(ready: Boolean): Boolean = ready && !inFlight && !terminal
    fun begin(ready: Boolean): Boolean {
        if (!canPay(ready)) return false
        inFlight = true
        return true
    }
    fun acceptsPaymentCallback(): Boolean = inFlight && !terminal
    fun finish(): Boolean {
        if (terminal) return false
        terminal = true
        inFlight = false
        return true
    }
}

/** Client-side test-mode guard; the server still owns the amount and approval. */
object TestOrderPolicy {
    fun isExactAmount(returned: Double, expected: Int): Boolean {
        return expected > 0 && returned.isFinite() &&
            returned >= 1.0 && returned <= Int.MAX_VALUE.toDouble() &&
            returned == expected.toDouble()
    }

    fun isValid(clientKey: String, customerKey: String, orderId: String, orderName: String, amount: Int): Boolean {
        return clientKey.startsWith("test_gck_") &&
            customerKey.length in 2..50 && customerKey.isNotBlank() &&
            orderId.isNotBlank() && orderId.length <= 64 &&
            orderName.isNotBlank() && amount > 0
    }
}
