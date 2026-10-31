import Foundation

class FreeLimitManager {
    static let shared = FreeLimitManager()

    // Deleted books release the free slot. Legacy permanent usage flags are ignored.
    func canAddBook(isPremium: Bool, currentBookCount: Int) -> Bool {
        BookAccessLogic.canAddBook(isPremium: isPremium, currentBookCount: currentBookCount)
    }
}
