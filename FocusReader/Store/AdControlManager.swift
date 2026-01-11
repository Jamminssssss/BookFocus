import Foundation
import Combine

@MainActor
final class AdControlManager: ObservableObject {
    static let shared = AdControlManager()

    /// 광고 제거 구매 여부
    @Published private(set) var isAdRemoved: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        bindPurchaseStatus()
    }

    // MARK: - Bind StoreKit Purchase Status
    private func bindPurchaseStatus() {
        // 앱 시작 시 즉시 반영
        isAdRemoved = StoreKitManager.shared.isPremium

        // 구매 상태 변경 감지
        NotificationCenter.default.publisher(for: .purchaseStatusChanged)
            .receive(on: RunLoop.main)
            .sink { _ in
                let premium = StoreKitManager.shared.isPremium
                self.isAdRemoved = premium
                print("🔄 광고 제거 상태 업데이트:", premium)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Ad Display Rules
extension AdControlManager {

    var shouldShowBannerAds: Bool {
        !isAdRemoved
    }

    var shouldShowInterstitialAds: Bool {
        !isAdRemoved
    }

    var shouldShowAppOpenAds: Bool {
        !isAdRemoved
    }
}
