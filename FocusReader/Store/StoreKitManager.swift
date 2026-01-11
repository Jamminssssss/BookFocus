import Foundation
import StoreKit
import Combine

@MainActor
class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    // 🔑 Product IDs
    private let premiumProductID = "com.Jaemin.FocusReader.premium"
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isPremium: Bool {
        purchasedProductIDs.contains(premiumProductID)
    }

    private var updateListenerTask: Task<Void, Never>?

    // MARK: - Init
    init() {
        updateListenerTask = listenForTransactions()

        Task {
            await requestProducts()
            await updateCustomerProductStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Products
    func requestProducts() async {
        do {
            isLoading = true
            products = try await Product.products(for: [premiumProductID])
            isLoading = false
            
            if products.isEmpty {
                print("⚠️ 제품을 찾을 수 없습니다. Products.storekit 설정을 확인하세요.")
            } else {
                print("📦 로드된 제품:", products.map { "\($0.displayName) - \($0.displayPrice)" })
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            print("❌ 제품 로드 실패:", error.localizedDescription)
        }
    }

    // MARK: - Purchase Premium
    func purchasePremium() async throws {
        guard let product = products.first(where: { $0.id == premiumProductID }) else {
            throw StoreError.productNotFound
        }

        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            await updateCustomerProductStatus()
            await transaction.finish()
            print("✅ 프리미엄 구매 완료: \(transaction.productID)")

        case .userCancelled:
            print("👤 구매 취소")
            throw StoreError.userCancelled

        case .pending:
            print("⏳ 구매 대기 중")
            throw StoreError.purchasePending

        @unknown default:
            break
        }
    }

    // MARK: - Restore
    func restorePurchases() async throws {
        isLoading = true
        defer { isLoading = false }

        try await AppStore.sync()
        await updateCustomerProductStatus()
        
        print("🔄 구매 복원 완료")
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try StoreKitManager.checkVerified(result)
                    await StoreKitManager.shared.updateCustomerProductStatus()
                    await transaction.finish()
                    print("🔄 트랜잭션 업데이트:", transaction.productID)
                } catch {
                    print("❌ 트랜잭션 검증 실패:", error)
                }
            }
        }
    }

    // MARK: - Entitlements
    func updateCustomerProductStatus() async {
        var purchased = Set<String>()

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try Self.checkVerified(result)
                if transaction.productType == .nonConsumable {
                    purchased.insert(transaction.productID)
                }
            } catch {
                print("❌ entitlement 오류:", error)
            }
        }

        purchasedProductIDs = purchased

        NotificationCenter.default.post(
            name: .purchaseStatusChanged,
            object: nil
        )
        
        print("💎 프리미엄 상태:", isPremium ? "활성화됨" : "비활성화됨")
    }

    // MARK: - Verification
    nonisolated static func checkVerified<T>(
        _ result: VerificationResult<T>
    ) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    // MARK: - Convenience
    var premiumProduct: Product? {
        products.first(where: { $0.id == premiumProductID })
    }
}

enum StoreError: Error, LocalizedError {
    case failedVerification
    case productNotFound
    case userCancelled
    case purchasePending

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "구매 검증에 실패했습니다"
        case .productNotFound:
            return "상품을 찾을 수 없습니다. 앱 설정을 확인해주세요."
        case .userCancelled:
            return "구매가 취소되었습니다"
        case .purchasePending:
            return "구매가 대기 중입니다"
        }
    }
}

extension Notification.Name {
    static let purchaseStatusChanged =
        Notification.Name("purchaseStatusChanged")
}
