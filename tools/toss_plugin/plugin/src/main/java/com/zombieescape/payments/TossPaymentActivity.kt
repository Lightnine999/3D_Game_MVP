package com.zombieescape.payments

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.tosspayments.paymentsdk.PaymentWidget
import com.tosspayments.paymentsdk.model.AgreementStatus
import com.tosspayments.paymentsdk.model.AgreementStatusListener
import com.tosspayments.paymentsdk.model.PaymentCallback
import com.tosspayments.paymentsdk.model.PaymentWidgetStatusListener
import com.tosspayments.paymentsdk.model.TossPaymentResult
import com.tosspayments.paymentsdk.view.Agreement
import com.tosspayments.paymentsdk.view.PaymentMethod

class TossPaymentActivity : AppCompatActivity() {
    companion object {
        const val KEY_CLIENT = "client_key"
        const val KEY_CUSTOMER = "customer_key"
        const val KEY_ORDER = "order_id"
        const val KEY_NAME = "order_name"
        const val KEY_AMOUNT = "amount"
        const val KEY_STATUS = "payment_status"
        const val KEY_PAYMENT = "payment_key"
    }

    private val attempt = PaymentAttemptState()

    private fun finishWithStatus(status: String, paymentKey: String = "", orderId: String = "", amount: Int = 0) {
        runOnUiThread {
            if (isDestroyed || !attempt.finish()) return@runOnUiThread
            val result = Intent()
                .putExtra(KEY_STATUS, status)
                .putExtra(KEY_ORDER, orderId)
                .putExtra(KEY_AMOUNT, amount)
            if (status == "authorized") result.putExtra(KEY_PAYMENT, paymentKey)
            setResult(if (status == "authorized") Activity.RESULT_OK else Activity.RESULT_CANCELED, result)
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setFinishOnTouchOutside(false)
        val clientKey = intent.getStringExtra(KEY_CLIENT).orEmpty()
        val customerKey = intent.getStringExtra(KEY_CUSTOMER).orEmpty()
        val orderId = intent.getStringExtra(KEY_ORDER).orEmpty()
        val orderName = intent.getStringExtra(KEY_NAME).orEmpty()
        val amount = intent.getIntExtra(KEY_AMOUNT, 0)
        if (!TestOrderPolicy.isValid(clientKey, customerKey, orderId, orderName, amount)) {
            finishWithStatus("invalid_test_parameters")
            return
        }

        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val notice = TextView(this).apply {
            text = "테스트 결제입니다. 실제 돈이 나가지 않습니다. 서버 확인 전에는 아이템을 지급하지 않습니다."
            textSize = 16f
            setPadding(24, 20, 24, 20)
        }
        val status = TextView(this).apply {
            text = "결제수단을 불러오는 중입니다…"
            textSize = 16f
            setPadding(24, 12, 24, 12)
        }
        val method = PaymentMethod(this)
        val agreement = Agreement(this)
        val content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        content.addView(method, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 450))
        content.addView(agreement, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 220))
        val scroll = ScrollView(this).apply { addView(content) }
        val payButton = Button(this).apply { text = "테스트 결제하기"; isEnabled = false }
        val closeButton = Button(this).apply {
            text = "취소"
            setOnClickListener { finishWithStatus("cancelled") }
        }
        root.addView(notice)
        root.addView(status)
        root.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(payButton)
        root.addView(closeButton)
        setContentView(root)

        var methodReady = false
        var agreementReady = false
        var agreed = false
        fun refreshButton() {
            payButton.isEnabled = !isDestroyed && !isFinishing &&
                attempt.canPay(methodReady && agreementReady && agreed)
        }
        fun onWidgetEvent(action: () -> Unit) {
            runOnUiThread {
                if (isDestroyed || isFinishing || attempt.terminal) return@runOnUiThread
                action()
                refreshButton()
            }
        }
        val widget = PaymentWidget(this, clientKey, customerKey)
        widget.renderPaymentMethods(method, amount, null, object : PaymentWidgetStatusListener {
            override fun onLoad() = onWidgetEvent {
                methodReady = true
                if (!attempt.inFlight) status.text = "결제수단을 선택하고 약관에 동의해 주세요."
            }
            override fun onFail(fail: TossPaymentResult.Fail) = onWidgetEvent {
                if (!attempt.inFlight) finishWithStatus("method_load_failed")
            }
        })
        widget.renderAgreement(agreement, object : PaymentWidgetStatusListener {
            override fun onLoad() = onWidgetEvent { agreementReady = true }
            override fun onFail(fail: TossPaymentResult.Fail) = onWidgetEvent {
                if (!attempt.inFlight) finishWithStatus("agreement_load_failed")
            }
        })
        widget.addAgreementStatusListener(object : AgreementStatusListener {
            override fun onAgreementStatusChanged(agreementStatus: AgreementStatus) = onWidgetEvent {
                agreed = agreementStatus.agreedRequiredTerms
            }
        })
        payButton.setOnClickListener {
            if (isDestroyed || isFinishing || !attempt.begin(methodReady && agreementReady && agreed)) return@setOnClickListener
            refreshButton() // Claim in-flight before the SDK can invoke synchronous callbacks.
            try {
                widget.requestPayment(PaymentMethod.PaymentInfo(orderId, orderName), object : PaymentCallback {
                    override fun onPaymentSuccess(success: TossPaymentResult.Success) {
                        runOnUiThread {
                            if (isDestroyed || isFinishing || !attempt.acceptsPaymentCallback()) return@runOnUiThread
                            if (success.orderId == orderId && TestOrderPolicy.isExactAmount(success.amount.toDouble(), amount) && success.paymentKey.isNotBlank()) {
                                finishWithStatus("authorized", success.paymentKey, success.orderId, amount)
                            } else {
                                finishWithStatus("invalid_payment_result")
                            }
                        }
                    }
                    override fun onPaymentFailed(fail: TossPaymentResult.Fail) {
                        runOnUiThread {
                            if (!isDestroyed && !isFinishing && attempt.acceptsPaymentCallback()) finishWithStatus("payment_failed")
                        }
                    }
                })
            } catch (_: Exception) {
                finishWithStatus("payment_failed")
            }
        }
    }

    @Deprecated("System back navigation is handled by Android")
    override fun onBackPressed() { finishWithStatus("cancelled") }
}
