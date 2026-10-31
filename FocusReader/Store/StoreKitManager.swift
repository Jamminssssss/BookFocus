import Foundation
import StoreKit
import Combine

@MainActor
class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    // 🔑 Product IDs (App Store Connect / .storekit 파일에 등록된 ID)
    private let subscriptionIDs = [
        "com.Jaemin.FocusReader.premium.monthly",
        "com.Jaemin.FocusReader.premium.yearly"
    ]
    
    // 🎨 테마 비소모품 상품 ID 추가
    private let themeIDs = [
        "com.Jaemin.FocusReader.theme.summer"
    ]
    
    @Published var products: [Product] = [] // 구독 상품 배열 (PurchaseView 용)
    @Published var themeProducts: [Product] = [] // 테마 상품 배열 (ThemeSelectionView 용)
    
    @Published var purchasedProductIDs: Set<String> = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 구매한 상품 중 하나라도 구독 상품 ID에 포함되어 있으면 Premium 상태로 간주
    var isPremium: Bool {
        !purchasedProductIDs.isDisjoint(with: Set(subscriptionIDs))
    }
    
    // 특정 테마를 구매했는지 확인하는 헬퍼 함수
    func hasPurchasedTheme(id: String) -> Bool {
        purchasedProductIDs.contains(id)
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
            
            // 구독 ID와 테마 ID를 모두 합쳐서 한 번에 로드
            let allIDs = subscriptionIDs + themeIDs
            let fetchedProducts = try await Product.products(for: allIDs)
            
            // 기존 구독 뷰에 영향을 주지 않도록 각각 필터링하여 분리 저장
            self.products = fetchedProducts
                .filter { subscriptionIDs.contains($0.id) }
                .sorted { $0.price < $1.price } // 구독은 가격 오름차순 정렬
            
            self.themeProducts = fetchedProducts
                .filter { themeIDs.contains($0.id) }
            
            isLoading = false
            
            if products.isEmpty && themeProducts.isEmpty {
                print("⚠️ 제품을 찾을 수 없습니다. Products.storekit 또는 App Store Connect 설정을 확인하세요.")
            } else {
                print("📦 로드된 구독 제품:", products.map { "\($0.displayName) - \($0.displayPrice)" })
                print("🎨 로드된 테마 제품:", themeProducts.map { "\($0.displayName) - \($0.displayPrice)" })
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            print("❌ 제품 로드 실패:", error.localizedDescription)
        }
    }

    // MARK: - Purchase Product
    // 특정 Product를 직접 전달받아 구매하도록 처리 (구독, 비소모품 모두 호환됨)
    func purchase(_ product: Product) async throws {
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            await updateCustomerProductStatus()
            await transaction.finish()
            print("✅ 상품 구매 완료: \(transaction.productID)")

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

        // currentEntitlements는 만료된 구독을 자동으로 걸러주고 현재 활성화된 것만 반환합니다.
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try Self.checkVerified(result)
                // 💡 [수정] 자동 갱신 구독(.autoRenewable) 뿐만 아니라 비소모품(.nonConsumable) 테마 구매도 반영
                if transaction.productType == .autoRenewable || transaction.productType == .nonConsumable {
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
        
        print("💎 프리미엄 상태:", isPremium ? "구독 중" : "구독 만료/미가입")
        print("🎨 구매한 테마 목록:", purchased.filter { themeIDs.contains($0) })
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
}

// MARK: - Errors
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
    static let purchaseStatusChanged = Notification.Name("purchaseStatusChanged")
}
