import Foundation
import StoreKit

@MainActor
enum AdConfiguration {
    enum DistributionEnvironment: String {
        case development
        case testFlight
        case appStore
    }

    private enum TestAdUnitID {
        static let banner = "ca-app-pub-3940256099942544/2435281174"
        static let appOpen = "ca-app-pub-3940256099942544/5575463023"
    }

    private enum ProductionAdUnitID {
        static let topBanner = "ca-app-pub-9940677842340433/1771857953"
        static let appOpen = "ca-app-pub-9940677842340433/6832612940"
        static let bottomBanner = "ca-app-pub-9940677842340433/1341624871"
    }

    private static func configuredValue(for key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else { return nil }
        return value
    }

    /// App Store에서 내려받은 운영 앱만 실제 광고를 사용한다.
    /// 환경 확인이 끝나기 전이나 검증에 실패하면 테스트 광고를 사용한다.
    private(set) static var distributionEnvironment: DistributionEnvironment = .development

    private static let environmentTask = Task<DistributionEnvironment, Never> {
#if targetEnvironment(simulator) || DEBUG
        return .development
#else
        if Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil {
            return .development
        }
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let transaction) = result else { return .development }
            switch transaction.environment {
            case .production: return .appStore
            case .sandbox: return .testFlight
            default: return .development
            }
        } catch {
            return .development
        }
#endif
    }

    /// 광고 요청 전에 호출하여 모든 광고 영역이 같은 검증 결과를 사용하게 한다.
    static func prepare() async {
        distributionEnvironment = await environmentTask.value
    }

    static var usesTestAds: Bool { distributionEnvironment != .appStore }
    static var applicationID: String? { configuredValue(for: "GADApplicationIdentifier") }
    static var topBannerAdUnitID: String {
        usesTestAds
            ? TestAdUnitID.banner
            : (configuredValue(for: "GADTopBannerAdUnitID") ?? ProductionAdUnitID.topBanner)
    }
    static var bottomBannerAdUnitID: String {
        usesTestAds
            ? TestAdUnitID.banner
            : (configuredValue(for: "GADBottomBannerAdUnitID") ?? ProductionAdUnitID.bottomBanner)
    }
    static var appOpenAdUnitID: String {
        usesTestAds
            ? TestAdUnitID.appOpen
            : (configuredValue(for: "GADAppOpenAdUnitID") ?? ProductionAdUnitID.appOpen)
    }
}
