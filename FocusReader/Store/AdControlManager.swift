import Foundation
import Combine

@MainActor
final class AdControlManager: ObservableObject {
    static let shared = AdControlManager()

    /// 광고 제거 구매 여부
    @Published private(set) var isAdRemoved: Bool = false
    @Published private(set) var isPurchaseStatusReady: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        bindPurchaseStatus()
    }

    // MARK: - Bind StoreKit Purchase Status
    private func bindPurchaseStatus() {
        // StoreKit 조회가 끝나기 전에는 기존 구독자에게 광고를 노출하지 않는다.
        isAdRemoved = StoreKitManager.shared.isPremium

        // 구매 상태 변경 감지
        NotificationCenter.default.publisher(for: .purchaseStatusChanged)
            .receive(on: RunLoop.main)
            .sink { _ in
                let premium = StoreKitManager.shared.isPremium
                self.isAdRemoved = premium
                self.isPurchaseStatusReady = true
                print("🔄 광고 제거 상태 업데이트:", premium)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Ad Display Rules
extension AdControlManager {

    var shouldShowBannerAds: Bool {
        isPurchaseStatusReady && !isAdRemoved
    }

    var shouldShowInterstitialAds: Bool {
        isPurchaseStatusReady && !isAdRemoved
    }

    var shouldShowAppOpenAds: Bool {
        isPurchaseStatusReady && !isAdRemoved
    }
}
