//
//  FocusReaderWidgetLiveActivity.swift
//  FocusReaderWidget
//
//  Created by JeaminPark on 12/12/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct FocusReaderWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct FocusReaderWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusReaderWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension FocusReaderWidgetAttributes {
    fileprivate static var preview: FocusReaderWidgetAttributes {
        FocusReaderWidgetAttributes(name: "World")
    }
}

extension FocusReaderWidgetAttributes.ContentState {
    fileprivate static var smiley: FocusReaderWidgetAttributes.ContentState {
        FocusReaderWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: FocusReaderWidgetAttributes.ContentState {
         FocusReaderWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: FocusReaderWidgetAttributes.preview) {
   FocusReaderWidgetLiveActivity()
} contentStates: {
    FocusReaderWidgetAttributes.ContentState.smiley
    FocusReaderWidgetAttributes.ContentState.starEyes
}
