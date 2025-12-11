//
//  ReadingTimerLiveActivity.swift
//  FocusReader
//
//  Live Activity UI 구현
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ReadingTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingTimerAttributes.self) { context in
            // Lock screen/banner UI
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.bookTitle)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text("Page \(context.state.currentPage) / \(context.state.totalPages)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack {
                    if context.state.isPaused {
                        Image(systemName: "pause.fill")
                            .foregroundColor(.orange)
                        Text("Paused")
                            .font(.caption2)
                    } else {
                        Text(timerInterval: context.state.startTime...Date.distantFuture, countsDown: false)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(Color.blue.opacity(0.2))
            .activitySystemActionForegroundColor(Color.black)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.state.bookTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Page \(context.state.currentPage)/\(context.state.totalPages)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        VStack {
                            Image(systemName: "pause.fill")
                                .foregroundColor(.orange)
                            Text("Paused")
                                .font(.caption2)
                        }
                    } else {
                        Text(timerInterval: context.state.startTime...Date.distantFuture, countsDown: false)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "book.fill")
                            .foregroundColor(.blue)
                        Text("Reading in progress...")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
            } compactTrailing: {
                if context.state.isPaused {
                    Image(systemName: "pause.fill")
                        .foregroundColor(.orange)
                } else {
                    Text(timerInterval: context.state.startTime...Date.distantFuture, countsDown: false)
                        .font(.caption2)
                        .monospacedDigit()
                        .frame(width: 50)
                }
            } minimal: {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
            }
        }
    }
}
