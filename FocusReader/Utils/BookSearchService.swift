import Foundation

enum BookSearchServiceError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The book service returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

struct BookSearchService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        text: String,
        queryPrefix: String,
        apiKey: String,
        targetIsEbook: Bool,
        maxResults: Int = 40
    ) async throws -> [SearchBookResult] {
        var googleError: Error?
        var googleBooks: [SearchBookResult] = []

        do {
            googleBooks = try await searchGoogleBooks(
                text: text,
                queryPrefix: queryPrefix,
                apiKey: apiKey,
                maxResults: maxResults
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            googleError = error

            // 잘못되었거나 제한 설정이 맞지 않는 API 키 때문에 전체 검색이 막히지 않게
            // 공개 검색 API로 한 번 더 시도한다.
            if !apiKey.isEmpty {
                do {
                    googleBooks = try await searchGoogleBooks(
                        text: text,
                        queryPrefix: queryPrefix,
                        apiKey: "",
                        maxResults: maxResults
                    )
                    googleError = nil
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    googleError = error
                }
            }
        }

        // Google 결과가 충분하면 불필요한 두 번째 네트워크 요청을 하지 않는다.
        if googleBooks.count >= 8 {
            return googleBooks
        }

        do {
            let openLibraryBooks = try await searchOpenLibrary(
                text: text,
                queryPrefix: queryPrefix,
                targetIsEbook: targetIsEbook,
                limit: min(maxResults, 30)
            )
            return merge(primary: googleBooks, fallback: openLibraryBooks, limit: maxResults)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if !googleBooks.isEmpty { return googleBooks }
            throw googleError ?? error
        }
    }

    private func searchGoogleBooks(
        text: String,
        queryPrefix: String,
        apiKey: String,
        maxResults: Int
    ) async throws -> [SearchBookResult] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        var queryItems = [
            URLQueryItem(name: "q", value: "\(queryPrefix)\(text)"),
            URLQueryItem(name: "maxResults", value: "\(min(max(maxResults, 1), 40))"),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "orderBy", value: "relevance")
        ]
        if !apiKey.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else { throw BookSearchServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        try validate(response: response, data: data)

        let result = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
        return (result.items ?? []).compactMap { item in
            guard let title = item.volumeInfo.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            let authors = item.volumeInfo.authors?.joined(separator: ", ") ?? "Unknown Author"
            let thumbnail = item.volumeInfo.imageLinks?.thumbnail?
                .replacingOccurrences(of: "http://", with: "https://")

            return SearchBookResult(
                id: item.id ?? UUID().uuidString,
                title: title,
                authors: authors,
                pageCount: item.volumeInfo.pageCount ?? 0,
                imageURL: thumbnail.flatMap(URL.init(string:)),
                thumbnailData: nil,
                isEbook: item.saleInfo?.isEbook ?? false
            )
        }
    }

    private func searchOpenLibrary(
        text: String,
        queryPrefix: String,
        targetIsEbook: Bool,
        limit: Int
    ) async throws -> [SearchBookResult] {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        let fieldName: String
        switch queryPrefix {
        case "intitle:": fieldName = "title"
        case "inauthor:": fieldName = "author"
        default: fieldName = "q"
        }
        components?.queryItems = [
            URLQueryItem(name: fieldName, value: text),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "fields", value: "key,title,author_name,cover_i,number_of_pages_median,ebook_access")
        ]

        guard let url = components?.url else { throw BookSearchServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("BookFocus/1.0 (\(Bundle.main.bundleIdentifier ?? "iOS"))", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BookSearchServiceError.invalidResponse
        }

        let result = try JSONDecoder().decode(OpenLibrarySearchAPIResponse.self, from: data)
        return (result.docs ?? []).enumerated().compactMap { index, document in
            guard let title = document.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            let coverURL = document.coverID.flatMap {
                URL(string: "https://covers.openlibrary.org/b/id/\($0)-M.jpg")
            }
            let ebookAccess = document.ebookAccess?.lowercased()
            let hasEbook = ebookAccess != nil && ebookAccess != "no_ebook"
            guard !targetIsEbook || hasEbook else { return nil }

            return SearchBookResult(
                id: "openlibrary:\(document.key ?? "\(index)-\(title)")",
                title: title,
                authors: document.authors?.joined(separator: ", ") ?? "Unknown Author",
                pageCount: document.pageCount ?? 0,
                imageURL: coverURL,
                thumbnailData: nil,
                // Open Library의 스캔/대여 가능 표시는 종이책 자체가 전자책이라는 뜻은 아니다.
                // 전자책 추가 화면에서 검색한 경우에만 전자책 결과로 취급한다.
                isEbook: targetIsEbook
            )
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookSearchServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(GoogleBooksAPIErrorResponse.self, from: data)
            let message = apiError?.error?.message ?? "Book search failed (HTTP \(httpResponse.statusCode))."
            throw BookSearchServiceError.server(message)
        }
    }

    private func merge(
        primary: [SearchBookResult],
        fallback: [SearchBookResult],
        limit: Int
    ) -> [SearchBookResult] {
        var seen = Set<String>()
        return (primary + fallback).filter { book in
            let key = "\(normalized(book.title))|\(normalized(book.authors))"
            return seen.insert(key).inserted
        }.prefix(limit).map { $0 }
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private struct GoogleBooksAPIErrorResponse: Decodable {
    let error: GoogleBooksAPIErrorBody?
}

private struct GoogleBooksAPIErrorBody: Decodable {
    let message: String?
}

private struct OpenLibrarySearchAPIResponse: Decodable {
    let docs: [OpenLibrarySearchDocument]?
}

private struct OpenLibrarySearchDocument: Decodable {
    let key: String?
    let title: String?
    let authors: [String]?
    let coverID: Int?
    let pageCount: Int?
    let ebookAccess: String?

    enum CodingKeys: String, CodingKey {
        case key
        case title
        case authors = "author_name"
        case coverID = "cover_i"
        case pageCount = "number_of_pages_median"
        case ebookAccess = "ebook_access"
    }
}
