import SwiftUI
import SwiftData
import Charts

struct ReadingInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ReadingSession.startTime, order: .reverse) private var sessions: [ReadingSession]
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @StateObject private var storeManager = StoreKitManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var selectedRange = 7
    @State private var showPurchase = false

    private var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    private var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    private var snapshots: [ReadingInsightSession] {
        sessions.map { ReadingInsightSession(startTime: $0.startTime, duration: $0.duration) }
    }
    private var chartMetrics: [DailyReadingMetric] {
        ReadingInsightsLogic.dailyMetrics(sessions: snapshots, numberOfDays: selectedRange)
    }
    private var todayDuration: TimeInterval {
        chartMetrics.last?.duration ?? 0
    }
    private var totalDuration: TimeInterval {
        snapshots.reduce(0) { $0 + $1.duration }
    }
    private var completedSessionCount: Int {
        snapshots.filter { $0.duration > 0 }.count
    }

    var body: some View {
        ZStack {
            paperColor.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    header
                    freeSummary
                    premiumSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .statusBarHidden(true)
        .fullScreenCover(isPresented: $showPurchase) { PurchaseView() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("insights.")
                    .font(.custom("ChalkboardSE-Bold", size: 24))
                Text("your reading, one page at a time")
                    .font(.custom("ChalkboardSE-Regular", size: 13))
                    .foregroundStyle(inkColor.opacity(0.58))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(inkColor.opacity(0.07), in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .foregroundStyle(inkColor)
        .padding(.top, 12)
    }

    private var freeSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("today")
                .font(.custom("ChalkboardSE-Bold", size: 17))
            HStack(spacing: 12) {
                summaryCell(value: formattedDuration(todayDuration), label: "reading time", icon: "timer")
                divider
                summaryCell(value: "\(completedSessionCount)", label: "total sessions", icon: "bookmark")
            }
            if completedSessionCount == 0 {
                Text("start a timer and your reading rhythm will appear here.")
                    .font(.custom("ChalkboardSE-Regular", size: 13))
                    .foregroundStyle(inkColor.opacity(0.58))
            } else {
                Text("all time · \(formattedDuration(totalDuration))")
                    .font(.custom("ChalkboardSE-Regular", size: 13))
                    .foregroundStyle(inkColor.opacity(0.58))
            }
        }
        .foregroundStyle(inkColor)
        .padding(18)
        .background(inkColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(inkColor.opacity(0.12), lineWidth: 1) }
    }

    private var premiumSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("reading patterns")
                    .font(.custom("ChalkboardSE-Bold", size: 19))
                Spacer()
                if storeManager.isPremium {
                    rangePicker
                } else {
                    Label("premium", systemImage: "crown.fill")
                        .font(.custom("ChalkboardSE-Regular", size: 12))
                }
            }

            ZStack {
                VStack(spacing: 22) {
                    readingChart
                    detailGrid
                }
                .blur(radius: storeManager.isPremium ? 0 : 3.5)
                .opacity(storeManager.isPremium ? 1 : 0.46)
                .allowsHitTesting(storeManager.isPremium)

                if !storeManager.isPremium { premiumOverlay }
            }
        }
        .foregroundStyle(inkColor)
        .padding(18)
        .background(paperColor, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(inkColor.opacity(0.18), lineWidth: 1.2) }
    }

    private var rangePicker: some View {
        HStack(spacing: 3) {
            ForEach([7, 30], id: \.self) { days in
                Button { withAnimation(.easeOut(duration: 0.2)) { selectedRange = days } } label: {
                    Text("\(days)d")
                        .font(.custom("ChalkboardSE-Bold", size: 12))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .foregroundStyle(selectedRange == days ? paperColor : inkColor.opacity(0.58))
                        .background(selectedRange == days ? inkColor : .clear, in: Capsule())
                }
            }
        }
        .padding(3)
        .background(inkColor.opacity(0.06), in: Capsule())
    }

    private var readingChart: some View {
        Chart(chartMetrics) { metric in
            BarMark(
                x: .value("Day", metric.day, unit: .day),
                y: .value("Minutes", metric.duration / 60)
            )
            .foregroundStyle(inkColor.opacity(metric.duration > 0 ? 0.82 : 0.12))
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: selectedRange == 7 ? .day : .weekOfYear)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .foregroundStyle(inkColor.opacity(0.52))
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisValueLabel().foregroundStyle(inkColor.opacity(0.46))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                    .foregroundStyle(inkColor.opacity(0.14))
                AxisTick().foregroundStyle(.clear)
            }
        }
        .frame(height: 170)
        .accessibilityLabel("Reading minutes chart")
    }

    private var detailGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            insightCell(value: String(localized: "\(ReadingInsightsLogic.currentStreak(sessions: snapshots)) days"), label: "current streak", icon: "flame")
            insightCell(value: formattedDuration(ReadingInsightsLogic.averageDuration(snapshots)), label: "average session", icon: "hourglass")
            insightCell(value: favoriteDay, label: "best reading day", icon: "calendar")
            insightCell(value: "\(books.filter(\.isCompleted).count)", label: "books completed", icon: "checkmark.circle")
        }
    }

    private var premiumOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 26, weight: .light))
            Text("see your reading rhythm")
                .font(.custom("ChalkboardSE-Bold", size: 21))
            Text("unlock trends, streaks and personal patterns\nthat grow with every session.")
                .font(.custom("ChalkboardSE-Regular", size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(inkColor.opacity(0.68))
            Button { showPurchase = true } label: {
                HStack(spacing: 8) {
                    Text("unlock insights")
                    Image(systemName: "arrow.right")
                }
                .font(.custom("ChalkboardSE-Bold", size: 16))
                .foregroundStyle(paperColor)
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background(inkColor, in: RoundedRectangle(cornerRadius: 15))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
    }

    private func summaryCell(value: String, label: LocalizedStringKey, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
            Text(value).font(.custom("ChalkboardSE-Bold", size: 24)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.custom("ChalkboardSE-Regular", size: 12)).foregroundStyle(inkColor.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(inkColor.opacity(0.12)).frame(width: 1, height: 72)
    }

    private func insightCell(value: String, label: LocalizedStringKey, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
            Text(value).font(.custom("ChalkboardSE-Bold", size: 17)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.custom("ChalkboardSE-Regular", size: 11)).foregroundStyle(inkColor.opacity(0.56))
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(inkColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
    }

    private var favoriteDay: String {
        guard let weekday = ReadingInsightsLogic.mostActiveWeekday(snapshots) else { return "—" }
        let symbols = Calendar.current.shortWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "—" }
        return symbols[weekday - 1]
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes >= 60 { return String(localized: "\(minutes / 60)h \(minutes % 60)m") }
        return String(localized: "\(minutes)m")
    }
}
