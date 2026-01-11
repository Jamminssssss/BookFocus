import SwiftUI
import GoogleMobileAds
import UIKit
import Combine

@MainActor
final class InterstitialViewModel: NSObject, ObservableObject, FullScreenContentDelegate {

    private var interstitialAd: InterstitialAd?
    private let adControlManager = AdControlManager.shared

    @Published private(set) var isAdReady = false
    private var isLoading = false

    private let adUnitID = "ca-app-pub-3940256099942544/4411468910" // 테스트용

    // MARK: - Load Ad
    func loadAd() async {
        // 광고 제거 구매 시 로드하지 않음
        guard adControlManager.shouldShowInterstitialAds else {
            print("🚫 광고제거 구매로 인해 전면광고 로드 중단")
            clearAd()
            return
        }

        // 이미 로딩 중이거나 광고가 있으면 중단
        guard !isLoading, interstitialAd == nil else { return }

        isLoading = true

        do {
            let ad = try await InterstitialAd.load(
                with: adUnitID,
                request: Request()
            )

            // 로드 도중 광고 제거 구매가 발생했을 수 있음
            guard adControlManager.shouldShowInterstitialAds else {
                isLoading = false
                return
            }

            ad.fullScreenContentDelegate = self
            interstitialAd = ad
            isAdReady = true
            print("✅ 전면광고 로드 완료")

        } catch {
            print("❌ 전면광고 로드 실패:", error.localizedDescription)
            clearAd()
        }

        isLoading = false
    }

    // MARK: - Show Ad
    func showAd() {
        // 광고 제거 구매 시 표시 안 함
        guard adControlManager.shouldShowInterstitialAds else {
            print("🚫 광고제거 구매로 인해 전면광고 표시 중단")
            clearAd()
            return
        }

        guard let ad = interstitialAd else {
            print("⚠️ 전면광고 준비 안됨")
            return
        }

        guard let rootVC = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
                print("⚠️ RootViewController 없음")
                return
        }

        ad.present(from: rootVC)
    }

    // MARK: - FullScreenContentDelegate

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        print("📊 전면광고 노출 기록")
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        print("🖱️ 전면광고 클릭")
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("🎬 전면광고 표시 시작")
    }

    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("⏳ 전면광고 닫히는 중")
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("✅ 전면광고 닫힘")
        clearAd()

        // 닫힌 후 다음 광고 미리 로드
        if adControlManager.shouldShowInterstitialAds {
            Task { await loadAd() }
        }
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        print("❌ 전면광고 표시 실패:", error.localizedDescription)
        clearAd()
    }

    // MARK: - Cleanup
    private func clearAd() {
        interstitialAd = nil
        isAdReady = false
        isLoading = false
    }
}
