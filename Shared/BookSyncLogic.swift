import Foundation

enum BookSyncLogic {
    static func merge(
        local: [SharedBookData],
        incoming: [SharedBookData],
        isFullSnapshot: Bool
    ) -> [SharedBookData] {
        var merged: [String: SharedBookData] = isFullSnapshot
            ? [:]
            : Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for receivedBook in incoming {
            if let localBook = localByID[receivedBook.id],
               localBook.lastUpdated > receivedBook.lastUpdated {
                merged[localBook.id] = localBook
            } else {
                merged[receivedBook.id] = receivedBook
            }
        }

        return merged.values.sorted { $0.createdAt > $1.createdAt }
    }
}
