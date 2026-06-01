import StoreKit
import SwiftUI

@MainActor
final class AdManager: ObservableObject {
    static let shared = AdManager()
    static let productId = "com.jamboree.adfree"
    private static let adFreeKey = "jamboree.adFree"

    @Published private(set) var isAdFree: Bool
    @Published private(set) var isPurchasing = false
    @Published var purchaseError: String?

    private init() {
        isAdFree = UserDefaults.standard.bool(forKey: Self.adFreeKey)
        Task { await refreshEntitlement() }
        Task { await listenForTransactions() }
    }

    func purchase() {
        guard !isAdFree else { return }
        Task { await doPurchase() }
    }

    func restorePurchases() {
        Task {
            isPurchasing = true
            defer { isPurchasing = false }
            do {
                try await AppStore.sync()
                await refreshEntitlement()
            } catch {
                purchaseError = error.localizedDescription
            }
        }
    }

    private func doPurchase() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            guard let product = try await Product.products(for: [Self.productId]).first else {
                purchaseError = "Product not available."
                return
            }
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let tx) = verification {
                await tx.finish()
                markAdFree()
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.productId {
                markAdFree()
                return
            }
        }
    }

    private func markAdFree() {
        isAdFree = true
        UserDefaults.standard.set(true, forKey: Self.adFreeKey)
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let tx) = result, tx.productID == Self.productId {
                await tx.finish()
                markAdFree()
            }
        }
    }
}
