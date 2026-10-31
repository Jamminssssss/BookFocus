import Foundation
@testable import BookFocusCore

let now = Date(timeIntervalSince1970: 1_000)
precondition(TimerLogic.elapsed(paused: 30, segmentStartedAt: now.addingTimeInterval(-15), now: now) == 45)
precondition(TimerLogic.elapsed(paused: 30, segmentStartedAt: nil, now: now) == 30)

precondition(TimerLogic.dueReminderIdentifiers(dateKey: "2026-09-23") == [
    "due-2026-09-23-1d",
    "due-2026-09-23-0d"
])

let legacyJSON = """
{
  "isRunning": false,
  "bookTitle": "Book",
  "currentPage": 10,
  "totalPages": 100,
  "elapsedTime": 120,
  "pausedTime": 120,
  "isTimerMode": false,
  "targetMinutes": 30,
  "bookID": "book-id"
}
""".data(using: .utf8)!
let legacyState = try JSONDecoder().decode(SharedTimerState.self, from: legacyJSON)
precondition(legacyState.startPage == nil)
precondition(legacyState.sessionOriginalStartTime == nil)
precondition(legacyState.lastUpdated == nil)
precondition(legacyState.sourceDevice == nil)
precondition(legacyState.hasActiveSession)

let command = TimerSyncCommand(action: .pause, bookID: "book-id", sentAt: now)
let decodedCommand = try JSONDecoder().decode(
    TimerSyncCommand.self,
    from: JSONEncoder().encode(command)
)
precondition(decodedCommand == command)

var widgetToggleState = SharedTimerState(
    isRunning: true,
    bookTitle: "Book",
    currentPage: 10,
    totalPages: 100,
    elapsedTime: 0,
    sessionStartTime: now.addingTimeInterval(-15),
    pausedTime: 30,
    isTimerMode: false,
    targetMinutes: 30,
    timerEndDate: nil,
    bookID: "book-id",
    startPage: 10,
    sessionOriginalStartTime: now.addingTimeInterval(-45)
)
widgetToggleState.toggleRunningState(now: now, source: "testWidget")
precondition(!widgetToggleState.isRunning)
precondition(widgetToggleState.pausedTime == 45)
widgetToggleState.toggleRunningState(now: now.addingTimeInterval(5), source: "testWidget")
precondition(widgetToggleState.isRunning)
precondition(widgetToggleState.sessionStartTime == now.addingTimeInterval(5))

let widgetState = WidgetTimerState(currentPage: 25, totalPages: 100)
precondition(widgetState.progress == 0.25)
precondition(widgetState.isEbook)
precondition(!WidgetTimerState(totalPages: 100, format: "physical").isEbook)

let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
let book = SharedBookData(
    id: "id",
    title: "Title",
    author: "Author",
    totalPages: 200,
    currentPage: 20,
    createdAt: .distantPast,
    lastUpdated: .distantFuture,
    checkoutDate: dueDate.addingTimeInterval(-86_400),
    dueDate: dueDate,
    format: "physical",
    loanStatus: "borrowed"
)
let decoded = try JSONDecoder().decode(SharedBookData.self, from: JSONEncoder().encode(book))
precondition(decoded == book)

let localOnlyBook = SharedBookData(
    id: "local-only",
    title: "Local",
    author: "Author",
    totalPages: 120,
    currentPage: 30,
    createdAt: .distantPast,
    lastUpdated: now,
    checkoutDate: nil,
    dueDate: nil,
    format: "physical",
    loanStatus: nil
)
let partialMerge = BookSyncLogic.merge(
    local: [book, localOnlyBook],
    incoming: [book],
    isFullSnapshot: false
)
precondition(Set(partialMerge.map(\.id)) == ["id", "local-only"])

let fullMerge = BookSyncLogic.merge(
    local: [book, localOnlyBook],
    incoming: [book],
    isFullSnapshot: true
)
precondition(fullMerge.map(\.id) == ["id"])

var insightCalendar = Calendar(identifier: .gregorian)
insightCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let insightNow = Date(timeIntervalSince1970: 1_800_000_000)
let insightToday = insightCalendar.startOfDay(for: insightNow)
let insightSessions = [
    ReadingInsightSession(startTime: insightToday.addingTimeInterval(3_600), duration: 1_800),
    ReadingInsightSession(startTime: insightToday.addingTimeInterval(-86_400 + 3_600), duration: 1_200),
    ReadingInsightSession(startTime: insightToday.addingTimeInterval(-172_800 + 3_600), duration: 600)
]
let sevenDays = ReadingInsightsLogic.dailyMetrics(
    sessions: insightSessions,
    numberOfDays: 7,
    calendar: insightCalendar,
    now: insightNow
)
precondition(sevenDays.count == 7)
precondition(sevenDays.last?.duration == 1_800)
precondition(ReadingInsightsLogic.currentStreak(sessions: insightSessions, calendar: insightCalendar, now: insightNow) == 3)
precondition(ReadingInsightsLogic.averageDuration(insightSessions) == 1_200)
precondition(ReadingInsightsLogic.longestDuration(insightSessions) == 1_800)

print("BookFocusCore checks passed")

// Free access depends on current holdings, including after deletion and subscription expiry.
precondition(BookAccessLogic.canAddBook(isPremium: false, currentBookCount: 0))
precondition(!BookAccessLogic.canAddBook(isPremium: false, currentBookCount: 1))
precondition(!BookAccessLogic.canAddBook(isPremium: false, currentBookCount: 3))
precondition(BookAccessLogic.canAddBook(isPremium: true, currentBookCount: 3))
var holdings = 0
precondition(BookAccessLogic.canAddBook(isPremium: false, currentBookCount: holdings))
holdings += 1
precondition(!BookAccessLogic.canAddBook(isPremium: false, currentBookCount: holdings))
holdings -= 1
precondition(BookAccessLogic.canAddBook(isPremium: false, currentBookCount: holdings))

// All receiving devices use the selected calendar day at 09:00, including DST boundaries.
for zoneID in ["Asia/Seoul", "Asia/Tokyo", "America/New_York", "Europe/Paris", "Australia/Sydney", "Pacific/Honolulu"] {
    let zone = TimeZone(identifier: zoneID)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    for dateKey in ["2026-03-08", "2026-11-01", "2027-01-01"] {
        let components = TimerLogic.dueReminderComponents(dateKey: dateKey, timeZone: zone)!
        precondition(components.hour == 9 && components.minute == 0 && components.second == 0)
        precondition(components.timeZone == nil)
        let localDate = calendar.date(from: components)!
        precondition(calendar.component(.hour, from: localDate) == 9)
        let previous = TimerLogic.dueReminderComponents(dateKey: dateKey, daysBefore: 1, timeZone: zone)!
        let previousDate = calendar.date(from: previous)!
        precondition(calendar.date(byAdding: .day, value: 1, to: previousDate) == localDate)
    }
}
precondition(TimerLogic.dueReminderComponents(dateKey: "2026-02-30") == nil)
precondition(TimerLogic.dueReminderComponents(dateKey: "invalid") == nil)
print("Book access and local due reminder checks passed")
