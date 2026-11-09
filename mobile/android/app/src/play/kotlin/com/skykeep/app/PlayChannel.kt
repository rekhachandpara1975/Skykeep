package com.skykeep.app

import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.UserChoiceBillingListener
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Play build only.
 *  - integrityToken: Play Integrity token for the 15 GB free cloud check.
 *  - connect: BillingClient with User Choice Billing (Google renders "Pay with Google Play" / "Pay with UPI").
 *    Only called when the server says play_billing_enabled = true (stays false until Google approval).
 *  - buy: launches the billing flow for a subscription base plan, with obfuscatedAccountId = sha256(user id).
 *  - queryPurchases: owned subscriptions, sent to the server on resume to recover purchases.
 * Events to Dart: "purchases" (Google Play path) and "userChoice" (user picked UPI → externalTransactionToken).
 * Acknowledgement happens server-side (play-purchase edge function) after verification.
 */
object PlayChannel {
    private var billing: BillingClient? = null

    private fun Purchase.toMap() = mapOf(
        "productId" to (products.firstOrNull() ?: ""),
        "purchaseToken" to purchaseToken,
        "state" to when (purchaseState) {
            Purchase.PurchaseState.PURCHASED -> "purchased"
            Purchase.PurchaseState.PENDING -> "pending"
            else -> "unspecified"
        },
        "acknowledged" to isAcknowledged,
    )

    private fun code(r: BillingResult) = when (r.responseCode) {
        BillingClient.BillingResponseCode.OK -> "ok"
        BillingClient.BillingResponseCode.USER_CANCELED -> "cancelled"
        BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> "already_owned"
        BillingClient.BillingResponseCode.BILLING_UNAVAILABLE -> "unavailable"
        else -> "error:${r.responseCode}:${r.debugMessage}"
    }

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
                "connect", "startUserChoiceBilling" -> {
                    if (call.argument<Boolean>("enabled") != true) return@setMethodCallHandler result.success("disabled")
                    billing?.let { if (it.isReady) return@setMethodCallHandler result.success("ready") }
                    val choice = UserChoiceBillingListener { d ->
                        activity.runOnUiThread {
                            channel.invokeMethod("userChoice", mapOf(
                                "externalTransactionToken" to d.externalTransactionToken,
                                "products" to d.products.map { it.id },
                            ))
                        }
                    }
                    val client = BillingClient.newBuilder(activity)
                        .setListener { r, purchases ->
                            activity.runOnUiThread {
                                channel.invokeMethod("purchases", mapOf(
                                    "result" to code(r),
                                    "purchases" to (purchases ?: emptyList()).map { it.toMap() },
                                ))
                            }
                        }
                        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
                        .enableUserChoiceBilling(choice)
                        .build()
                    billing = client
                    client.startConnection(object : BillingClientStateListener {
                        override fun onBillingSetupFinished(r: BillingResult) {
                            activity.runOnUiThread { result.success(if (r.responseCode == BillingClient.BillingResponseCode.OK) "ready" else code(r)) }
                        }
                        override fun onBillingServiceDisconnected() { billing = null }
                    })
                }
                "buy" -> {
                    val client = billing ?: return@setMethodCallHandler result.error("not_ready", "billing not connected", null)
                    val productId = call.argument<String>("productId") ?: return@setMethodCallHandler result.error("args", "productId", null)
                    val basePlanId = call.argument<String>("basePlanId")
                    val accountId = call.argument<String>("accountId") ?: return@setMethodCallHandler result.error("args", "accountId", null)
                    val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(
                        QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(productId).setProductType(BillingClient.ProductType.SUBS).build()
                    )).build()
                    client.queryProductDetailsAsync(params) { r, details ->
                        activity.runOnUiThread {
                            val pd = details.firstOrNull()
                            if (r.responseCode != BillingClient.BillingResponseCode.OK || pd == null) {
                                return@runOnUiThread result.success("error:product_not_found")
                            }
                            val offer = pd.subscriptionOfferDetails?.firstOrNull { basePlanId == null || it.basePlanId == basePlanId }
                                ?: return@runOnUiThread result.success("error:base_plan_not_found")
                            val flow = BillingFlowParams.newBuilder()
                                .setProductDetailsParamsList(listOf(
                                    BillingFlowParams.ProductDetailsParams.newBuilder()
                                        .setProductDetails(pd).setOfferToken(offer.offerToken).build()
                                ))
                                .setObfuscatedAccountId(accountId)
                                .build()
                            result.success(code(client.launchBillingFlow(activity, flow)))
                        }
                    }
                }
                "queryPurchases" -> {
                    val client = billing ?: return@setMethodCallHandler result.success(emptyList<Map<String, Any>>())
                    client.queryPurchasesAsync(
                        QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()
                    ) { _, purchases -> activity.runOnUiThread { result.success(purchases.map { it.toMap() }) } }
                }
                else -> result.notImplemented()
            }
        }
    }
}
