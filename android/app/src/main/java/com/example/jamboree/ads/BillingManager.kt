package com.example.jamboree.ads

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams

/**
 * Google Play Billing wiring for the one-time "remove ads" upgrade
 * ([AdManager.SKU]). Mirrors the StoreKit flow on iOS: query the product for
 * its localised price, launch the purchase, acknowledge it, and persist the
 * entitlement through [AdManager]. Owned purchases are re-queried on connect
 * and on demand (restore) so the upgrade survives reinstalls.
 *
 * State is exposed as Compose-observable properties; Play Billing delivers all
 * callbacks on the main thread, so mutating them here is safe.
 */
class BillingManager(context: Context) {
    private val appContext = context.applicationContext
    private var productDetails: ProductDetails? = null

    var adFree by mutableStateOf(AdManager.isAdFree(appContext)); private set
    var purchasing by mutableStateOf(false); private set
    /** Localised price string once the product loads; null until then. */
    var price by mutableStateOf<String?>(null); private set
    var error by mutableStateOf<String?>(null)

    private val purchasesListener = PurchasesUpdatedListener { result, purchases ->
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK ->
                purchases?.forEach { handlePurchase(it) } ?: run { purchasing = false }
            BillingClient.BillingResponseCode.USER_CANCELED ->
                purchasing = false
            else -> {
                purchasing = false
                error = result.debugMessage.ifBlank { "Purchase failed." }
            }
        }
    }

    private val client = BillingClient.newBuilder(appContext)
        .setListener(purchasesListener)
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()
        )
        .build()

    init { connect() }

    private fun connect() {
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    queryProduct()
                    queryOwnedPurchases()
                }
            }
            override fun onBillingServiceDisconnected() {
                // Reconnected lazily on the next purchase/restore action.
            }
        })
    }

    private fun queryProduct() {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(AdManager.SKU)
                        .setProductType(BillingClient.ProductType.INAPP)
                        .build()
                )
            ).build()
        client.queryProductDetailsAsync(params) { result, list ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                productDetails = list.firstOrNull()
                price = productDetails?.oneTimePurchaseOfferDetails?.formattedPrice
            }
        }
    }

    private fun queryOwnedPurchases() {
        client.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
        ) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                purchases.forEach { handlePurchase(it) }
            }
        }
    }

    /** Launches the Play purchase sheet. Must be called from an [Activity]. */
    fun purchase(activity: Activity) {
        if (adFree) return
        val details = productDetails
        if (details == null) {
            error = "Product not available yet. Try again in a moment."
            if (!client.isReady) connect()
            return
        }
        purchasing = true
        error = null
        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(details)
                        .build()
                )
            ).build()
        val result = client.launchBillingFlow(activity, flowParams)
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            purchasing = false
            error = result.debugMessage.ifBlank { "Could not start purchase." }
        }
    }

    /** Re-checks Play for an existing entitlement (restore after reinstall). */
    fun restore() {
        error = null
        if (!client.isReady) { connect(); return }
        queryOwnedPurchases()
    }

    private fun handlePurchase(purchase: Purchase) {
        if (purchase.products.none { it == AdManager.SKU }) return
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) {
            // Pending (e.g. slow card / parental approval) — don't grant yet.
            purchasing = false
            return
        }
        AdManager.setAdFree(appContext, true)
        adFree = true
        purchasing = false
        if (!purchase.isAcknowledged) {
            val ackParams = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken)
                .build()
            client.acknowledgePurchase(ackParams) { /* best-effort */ }
        }
    }

    fun release() {
        client.endConnection()
    }
}
