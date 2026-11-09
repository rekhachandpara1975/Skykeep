package com.skykeep.app

import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.UserChoiceBillingListener
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Play build: Play Integrity token for the 15 GB free cloud check, and the User Choice Billing
 * path (Google-rendered choice screen). Billing is only started when the server says
 * play_billing_enabled = true, which stays false until Google approval (see docs/play-setup.md).
 */
object PlayChannel {
    private var billing: BillingClient? = null

    fun register(activity: MainActivity, engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app/play")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "integrityToken" -> {
                    val nonce = call.argument<String>("nonce") ?: return@setMethodCallHandler result.error("nonce", "missing", null)
                    IntegrityManagerFactory.create(activity.applicationContext)
                        .requestIntegrityToken(IntegrityTokenRequest.builder().setNonce(nonce).build())
                        .addOnSuccessListener { result.success(it.token()) }
                        .addOnFailureListener { result.error("integrity", it.message, null) }
                }
                "startUserChoiceBilling" -> {
                    if (call.argument<Boolean>("enabled") != true) return@setMethodCallHandler result.success("disabled")
                    val listener = UserChoiceBillingListener { details ->
                        channel.invokeMethod("userChoice", mapOf(
                            "externalTransactionToken" to details.externalTransactionToken,
                            "products" to details.products.map { it.id },
                        ))
                    }
                    val client = BillingClient.newBuilder(activity)
                        .setListener { _, _ -> }
                        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
                        .enableUserChoiceBilling(listener)
                        .build()
                    billing = client
                    client.startConnection(object : BillingClientStateListener {
                        override fun onBillingSetupFinished(r: BillingResult) { result.success(if (r.responseCode == BillingClient.BillingResponseCode.OK) "ready" else "error:${r.debugMessage}") }
                        override fun onBillingServiceDisconnected() {}
                    })
                }
                else -> result.notImplemented()
            }
        }
    }
}
