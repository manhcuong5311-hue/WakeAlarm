import Foundation
import StoreKit
import Combine

/// StoreKit 2 wrapper for WakeLock Premium (one-time purchase).
///
/// ## Usage
/// ```swift
/// @ObservedObject var pm = PremiumManager.shared
/// if pm.isPremium { ... }
/// await pm.purchase()
/// await pm.restorePurchases()
/// ```
@MainActor
final class PremiumManager: ObservableObject {

    static let shared = PremiumManager()

    // Product ID configured in App Store Connect
    static let productID = "com.SamCorp.WakeLock.premium"
    private static let udKey = "wakelock.premium"

    // MARK: - Published

    @Published private(set) var isPremium: Bool
    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?

    // MARK: - Private

    private var transactionTask: Task<Void, Never>?

    private init() {
        isPremium = UserDefaults.standard.bool(forKey: Self.udKey)
        transactionTask = startTransactionListener()
        Task { await loadProduct() }
        Task { await refreshEntitlements() }
    }

    deinit { transactionTask?.cancel() }

    // MARK: - Product

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            print("[PremiumManager] Product load error: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product, !isLoading else { return }
        isLoading      = true
        purchaseError  = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let tx = try checkVerified(verification)
                await refreshEntitlements()
                await tx.finish()
            case .pending:
                break   // Ask-to-Buy or SCA pending
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading     = true
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = "Restore failed. Please try again."
        }
        isLoading = false
    }

    // MARK: - Private helpers

    private func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  tx.productID == Self.productID,
                  tx.revocationDate == nil else { continue }
            setPremium(true)
            return
        }
    }

    private func startTransactionListener() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let tx) = result, tx.productID == Self.productID {
                    await self.refreshEntitlements()
                    await tx.finish()
                }
            }
        }
    }

    private func setPremium(_ value: Bool) {
        isPremium = value
        UserDefaults.standard.set(value, forKey: Self.udKey)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe):       return safe
        }
    }
}
