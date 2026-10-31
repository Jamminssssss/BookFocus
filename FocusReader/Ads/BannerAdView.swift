import SwiftUI
import GoogleMobileAds
import UIKit

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    @ObservedObject private var adControlManager = AdControlManager.shared

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = UIApplication.shared
            .connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        banner.delegate = context.coordinator
        banner.isHidden = true

        if adControlManager.shouldShowBannerAds {
            banner.load(Request())
        }

        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        banner.isHidden = !adControlManager.shouldShowBannerAds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            guard AdControlManager.shared.shouldShowBannerAds else {
                bannerView.isHidden = true
                return
            }
            bannerView.alpha = 0
            bannerView.isHidden = false
            UIView.animate(withDuration: 0.25) {
                bannerView.alpha = 1
            }
        }

        func bannerView(
            _ bannerView: BannerView,
            didFailToReceiveAdWithError error: Error
        ) {
            print("❌ Banner Error:", error.localizedDescription)
            bannerView.isHidden = true
        }
    }
}

private func bannerHeight(
    horizontal: UserInterfaceSizeClass?,
    vertical: UserInterfaceSizeClass?
) -> CGFloat {
    if horizontal == .regular && vertical == .compact { return 90 }
    if horizontal == .regular { return 100 }
    if horizontal == .compact && vertical == .compact { return 32 }
    return 50
}

struct AdaptiveTopBannerView: View {
    @State private var isAdConfigurationReady = false
    @ObservedObject private var adControlManager = AdControlManager.shared
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        Group {
            if isAdConfigurationReady && adControlManager.shouldShowBannerAds {
                GeometryReader { geo in
                    BannerAdView(adUnitID: AdConfiguration.topBannerAdUnitID)
                        .frame(
                            width: geo.size.width,
                            height: bannerHeight(horizontal: hSize, vertical: vSize)
                        )
                }
                .frame(height: bannerHeight(horizontal: hSize, vertical: vSize))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await AdConfiguration.prepare()
            isAdConfigurationReady = true
        }
    }
}

struct AdaptiveBottomBannerView: View {
    @State private var isAdConfigurationReady = false
    @ObservedObject private var adControlManager = AdControlManager.shared
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        Group {
            if isAdConfigurationReady && adControlManager.shouldShowBannerAds {
                GeometryReader { geo in
                    BannerAdView(adUnitID: AdConfiguration.bottomBannerAdUnitID)
                        .frame(
                            width: geo.size.width,
                            height: bannerHeight(horizontal: hSize, vertical: vSize)
                        )
                }
                .frame(height: bannerHeight(horizontal: hSize, vertical: vSize))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await AdConfiguration.prepare()
            isAdConfigurationReady = true
        }
    }
}
