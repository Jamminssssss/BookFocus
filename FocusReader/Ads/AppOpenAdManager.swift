import SwiftUI
import GoogleMobileAds
import Combine

@MainActor
final class AppOpenAdManager: NSObject, ObservableObject, FullScreenContentDelegate {

    static let shared = AppOpenAdManager()

    @Published private(set) var isAdLoading = false
    @Published private(set) var isAdShowing = false

    private var appOpenAd: AppOpenAd?
    private var loadTime: Date?

    // ⏱️ 유효 시간 (4시간)
    private let adValidityDuration: TimeInterval = 60 * 60 * 4

    // ⏱️ 연속 표시 방지 쿨타임 (3시간) - 앱 종료 후에도 유지
    private let minimumPresentInterval: TimeInterval = 60 * 60 * 3
    
    // ✅ UserDefaults로 지속 저장
    private let lastPresentedTimeKey = "AppOpenAdLastPresentedTime"
    private var lastPresentedTime: Date? {
        get {
            UserDefaults.standard.object(forKey: lastPresentedTimeKey) as? Date
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date, forKey: lastPresentedTimeKey)
                print("💾 광고 표시 시간 저장: \(date)")
            } else {
                UserDefaults.standard.removeObject(forKey: lastPresentedTimeKey)
            }
        }
    }

    private let adControlManager = AdControlManager.shared

    private override init() {
        super.init()
        printCooldownStatus() // 초기화 시 쿨타임 상태 출력
    }

    // MARK: - Load
    func loadAd() async {
        guard adControlManager.shouldShowAppOpenAds else {
            clearAdsAfterPurchase()
            return
        }

        guard !isAdLoading, !isAdAvailable() else { return }

        isAdLoading = true

        do {
            let ad = try await AppOpenAd.load(
                with: "ca-app-pub-3940256099942544/5575463023", // ⚠️ 실 ID로 교체
                request: Request()
            )

            guard adControlManager.shouldShowAppOpenAds else {
                isAdLoading = false
                return
            }

            ad.fullScreenContentDelegate = self
            appOpenAd = ad
            loadTime = Date()

            print("✅ App Open Ad 로드 완료")

        } catch {
            print("❌ App Open Ad 로드 실패:", error.localizedDescription)
        }

        isAdLoading = false
    }

    // MARK: - Show
    func showAdIfAvailable() async {
        guard adControlManager.shouldShowAppOpenAds else {
            clearAdsAfterPurchase()
            return
        }

        guard !isAdShowing else { return }

        guard canPresentNow() else {
            printCooldownStatus()
            return
        }

        guard isAdAvailable(), let ad = appOpenAd else {
            await loadAd()
            return
        }

        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?
            .windows
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {

            print("❌ rootViewController 없음")
            return
        }

        print("🎬 App Open Ad 표시")
        isAdShowing = true
        lastPresentedTime = Date() // ✅ UserDefaults에 자동 저장
        ad.present(from: rootVC)
    }


    // MARK: - Helpers
    private func isAdAvailable() -> Bool {
        guard let loadTime else { return false }
        return appOpenAd != nil &&
        Date().timeIntervalSince(loadTime) < adValidityDuration
    }

    private func canPresentNow() -> Bool {
        guard let last = lastPresentedTime else { return true }
        return Date().timeIntervalSince(last) > minimumPresentInterval
    }
    
    // ✅ 쿨타임 상태 출력 (디버깅용)
    private func printCooldownStatus() {
        guard let last = lastPresentedTime else {
            print("⏱️ 광고 쿨타임: 없음 (첫 실행)")
            return
        }
        
        let elapsed = Date().timeIntervalSince(last)
        let remaining = max(0, minimumPresentInterval - elapsed)
        
        if remaining > 0 {
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            print("⏱️ 광고 쿨타임 남음: \(hours)시간 \(minutes)분")
        } else {
            print("✅ 광고 쿨타임 완료 (표시 가능)")
        }
    }

    func clearAdsAfterPurchase() {
        appOpenAd = nil
        loadTime = nil
        isAdLoading = false
        isAdShowing = false
        // ✅ 구매 시에는 쿨타임도 초기화 (선택사항)
        // lastPresentedTime = nil
    }

    // MARK: - Delegate
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        isAdShowing = true
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("✖️ App Open Ad 닫힘")
        appOpenAd = nil
        isAdShowing = false

        if adControlManager.shouldShowAppOpenAds {
            Task { await loadAd() }
        }
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        print("❌ App Open Ad 표시 실패:", error.localizedDescription)
        appOpenAd = nil
        isAdShowing = false

        if adControlManager.shouldShowAppOpenAds {
            Task { await loadAd() }
        }
    }
}
