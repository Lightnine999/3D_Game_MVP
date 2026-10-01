package com.zombieescape.payments

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TestOrderPolicyTest {
    @Test fun paymentAttemptCannotReenterOrFinishTwice() {
        val attempt = PaymentAttemptState()
        assertFalse(attempt.begin(false))
        assertTrue(attempt.canPay(true))
        assertTrue(attempt.begin(true))
        assertTrue(attempt.acceptsPaymentCallback())
        assertFalse(attempt.canPay(true)) // A late agreement callback must not re-enable payment.
        assertFalse(attempt.begin(true))
        assertTrue(attempt.finish())
        assertFalse(attempt.acceptsPaymentCallback())
        assertFalse(attempt.finish()) // success/failure/cancel races deliver only one result.
        assertFalse(attempt.begin(true))
        assertFalse(attempt.canPay(true))
    }

    @Test fun cancellationBeforeLoadIgnoresLateReadiness() {
        val attempt = PaymentAttemptState()
        assertTrue(attempt.finish())
        assertFalse(attempt.canPay(true))
        assertFalse(attempt.begin(true))
        assertFalse(attempt.acceptsPaymentCallback())
        assertFalse(attempt.finish())
    }

    @Test fun callbackAmountMustBeExactFinitePositiveInt() {
        assertTrue(TestOrderPolicy.isExactAmount(1100.0, 1100))
        assertTrue(TestOrderPolicy.isExactAmount(Int.MAX_VALUE.toDouble(), Int.MAX_VALUE))
        for (invalid in listOf(1100.01, 1099.99, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, 0.0, -1.0)) {
            assertFalse(TestOrderPolicy.isExactAmount(invalid, 1100))
        }
        assertFalse(TestOrderPolicy.isExactAmount(Int.MAX_VALUE.toDouble() + 1.0, Int.MAX_VALUE))
        assertFalse(TestOrderPolicy.isExactAmount(0.0, 0))
    }

    @Test fun acceptsOnlyCompleteTestWidgetOrder() {
        assertTrue(TestOrderPolicy.isValid("test_gck_dummy", "customer-123456", "order-123", "Test pack", 1100))
        assertFalse(TestOrderPolicy.isValid("test_ck_dummy", "customer-123456", "order-123", "Test pack", 1100))
        assertFalse(TestOrderPolicy.isValid("live_gck_dummy", "customer-123456", "order-123", "Test pack", 1100))
        assertFalse(TestOrderPolicy.isValid("test_gck_dummy", "", "order-123", "Test pack", 1100))
        assertFalse(TestOrderPolicy.isValid("test_gck_dummy", "customer-123456", "", "Test pack", 1100))
        assertFalse(TestOrderPolicy.isValid("test_gck_dummy", "customer-123456", "order-123", "", 1100))
        assertFalse(TestOrderPolicy.isValid("test_gck_dummy", "customer-123456", "order-123", "Test pack", 0))
    }
}
