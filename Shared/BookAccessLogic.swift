import Foundation

enum BookAccessLogic {
    static func canAddBook(isPremium: Bool, currentBookCount: Int) -> Bool {
        isPremium || currentBookCount < 1
    }
}
