import Foundation

enum GoogleBooksConfiguration {
    static var apiKey: String {
        let value = Bundle.main.infoDictionary?["GoogleBooksAPIKey"] as? String ?? ""
        return value.hasPrefix("$(") ? "" : value
    }
}
