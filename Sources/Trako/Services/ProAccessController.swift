import Foundation
import StoreKit

@MainActor
final class ProAccessController: ObservableObject {
    static let productID = "com.alixkyle.trako.pro"

    @Published private(set) var isProUnlocked = false
    @Published private(set) var product: Product?
    @Published private(set) var purchaseInFlight = false
    @Published var lastErrorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { await listenForTransactions() }
        Task { await refreshEntitlements() }
        Task { await loadProduct() }
    }

    deinit {
        updatesTask?.cancel()
    }

    var canUseProjects: Bool {
        isProUnlocked
    }

    func refreshEntitlements() async {
        var unlocked = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }
            if transaction.productID == Self.productID {
                unlocked = true
            }
        }

        if UserDefaults.standard.bool(forKey: Self.testingUnlockKey) {
            unlocked = true
        }

        isProUnlocked = unlocked
    }

    var isTestingUnlockEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.testingUnlockKey)
    }

    func setTestingUnlocked(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.testingUnlockKey)
        Task { await refreshEntitlements() }
    }

    /// Local `.build` / Xcode installs — not for App Store release configuration.
    static var shouldAutoEnableTestingUnlock: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/.build/") || path.contains("/DerivedData/")
    }

    private static let testingUnlockKey = "trako-pro-testing-unlocked"

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func purchase() async {
        guard let product else {
            lastErrorMessage = "Trako Pro is not available yet. Set up the product in App Store Connect."
            return
        }

        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else {
                continue
            }
            await transaction.finish()
            await refreshEntitlements()
        }
    }
}
