//
//  FocusReaderWidgetControl.swift
//  FocusReaderWidget
//
//  Created by JeaminPark on 12/12/25.
//

import AppIntents
import SwiftUI
import WidgetKit

struct FocusReaderWidgetControl: ControlWidget {
    static let kind: String = "com.Jaemin.FocusReader.FocusReaderWidget"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Start Timer",
                isOn: value.isRunning,
                action: StartTimerIntent(value.name)
            ) { isRunning in
                Label(isRunning ? "On" : "Off", systemImage: "timer")
            }
        }
        .displayName("Reading Timer")
        .description("Start or pause your active BookFocus reading session.")
    }
}

extension FocusReaderWidgetControl {
    struct Value {
        var isRunning: Bool
        var name: String
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: TimerConfiguration) -> Value {
            FocusReaderWidgetControl.Value(isRunning: false, name: configuration.timerName)
        }

        func currentValue(configuration: TimerConfiguration) async throws -> Value {
            let isRunning = TimerStateManager.shared.loadActiveState()?.isRunning ?? false
            return FocusReaderWidgetControl.Value(isRunning: isRunning, name: configuration.timerName)
        }
    }
}

struct TimerConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Timer Name Configuration"

    @Parameter(title: "Timer Name", default: "Timer")
    var timerName: String
}

struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start a timer"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Timer Name")
    var name: String

    @Parameter(title: "Timer is running")
    var value: Bool

    init() {}

    init(_ name: String) {
        self.name = name
    }

    func perform() async throws -> some IntentResult {
        guard var state = TimerStateManager.shared.loadActiveState(), state.hasActiveSession else {
            return .result()
        }

        if value != state.isRunning {
            state.toggleRunningState(source: "controlWidget")
        }

        TimerStateManager.shared.saveState(state)
        if let defaults = UserDefaults(suiteName: AppGroupKey.suiteName) {
            defaults.set("toggle", forKey: AppGroupKey.widgetAction)
            defaults.set(state.bookID, forKey: AppGroupKey.widgetActionBookID)
        }
        return .result()
    }
}
