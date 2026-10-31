//
//  FocusManager.swift
//  FocusReader
//

import Foundation
import FamilyControls
import ManagedSettings
import Combine

@MainActor
final class FocusManager: ObservableObject {

    static let shared = FocusManager()

    @Published var isAuthorized: Bool = false
    @Published var isFocusModeActive: Bool = false

    @Published var focusModeEnabled: Bool {
        didSet {
            UserDefaults(suiteName: appGroupID)?.set(focusModeEnabled, forKey: Keys.focusModeEnabled)
        }
    }

    @Published var activitySelection: FamilyActivitySelection {
        didSet { saveSelection() }
    }

    private let store = ManagedSettingsStore()
    private let center = AuthorizationCenter.shared
    private let appGroupID = "group.com.Jaemin.FocusReader"

    private enum Keys {
        static let focusModeEnabled  = "focusModeEnabled"
        static let activitySelection = "focusActivitySelection"
        static let watchFocusActive  = "watchFocusModeActive"
    }

    private init() {
        let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader")
        self.focusModeEnabled = defaults?.bool(forKey: Keys.focusModeEnabled) ?? false
        self.activitySelection = FocusManager.loadSelection()
        Task { await checkAuthorization() }
    }

    func requestAuthorization() async {
        do {
            try await center.requestAuthorization(for: .individual)
            isAuthorized = (center.authorizationStatus == .approved)
        } catch {
            isAuthorized = false
            print("⚠️ FocusManager: 권한 요청 실패 — \(error.localizedDescription)")
        }
    }

    func checkAuthorization() async {
        isAuthorized = (center.authorizationStatus == .approved)
    }

    func enableFocusMode() {
        guard focusModeEnabled, isAuthorized else { return }

        let apps       = activitySelection.applicationTokens
        let categories = activitySelection.categoryTokens
        let domains    = activitySelection.webDomainTokens

        store.shield.applications          = apps.isEmpty       ? nil : apps
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains            = domains.isEmpty    ? nil : domains

        isFocusModeActive = true
        syncToWatch()
        print("🛡 Focus Mode ON — \(apps.count)개 앱 차단")
    }

    func disableFocusMode() {
        store.shield.applications          = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains            = nil

        isFocusModeActive = false
        syncToWatch()
        print("🛡 Focus Mode OFF")
    }

    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(activitySelection) else { return }
        UserDefaults(suiteName: appGroupID)?.set(data, forKey: Keys.activitySelection)
    }

    private static func loadSelection() -> FamilyActivitySelection {
        guard let data = UserDefaults(suiteName: "group.com.Jaemin.FocusReader")?.data(forKey: "focusActivitySelection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    private func syncToWatch() {
        UserDefaults(suiteName: appGroupID)?.set(isFocusModeActive, forKey: Keys.watchFocusActive)
    }
}
