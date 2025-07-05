import Foundation


class PointFileDownloader {
    private let urlSession: URLSessionProtocol
    
    init(urlSession: URLSessionProtocol = URLSession.shared) {
        self.urlSession = urlSession
    }
    
    func downloadFiles(from pageURL: URL, saveHandler: @escaping (_ date: Date, _ fileData: Data, _ fileName: String) -> Void) async throws {
        let pageRequest = URLRequest(url: pageURL)
        let htmlData = try await urlSession.data(for: pageRequest).0
        guard let htmlString = String(data: htmlData, encoding: .utf8) else { return }
        
        let date = try fetchCurrentDataDate(fromHTML: htmlString)
        let links = extractXLSXLinks(from: htmlString)
        
        for link in links {
            // Handle both absolute and relative URLs
            let fullURL: URL
            if link.hasPrefix("http") {
                guard let url = URL(string: link) else { continue }
                fullURL = url
            } else {
                // For relative URLs, combine with base URL
                let baseURL = pageURL.deletingLastPathComponent()
                guard let url = URL(string: link, relativeTo: baseURL) else { continue }
                fullURL = url
            }
            do {
                let request = URLRequest(url: fullURL)
                let data = try await urlSession.data(for: request).0
                let filename = fullURL.lastPathComponent
                saveHandler(date, data, filename)
            } catch {
                continue // skip file on error
            }
        }
    }
    
    func fetchCurrentDataDate(from pageURL: URL) async throws -> Date {
        let request = URLRequest(url: pageURL)
        let htmlData = try await urlSession.data(for: request).0
        guard let htmlString = String(data: htmlData, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return try fetchCurrentDataDate(fromHTML: htmlString)
    }
    
    private func fetchCurrentDataDate(fromHTML html: String) throws -> Date {
        if let date = extractDateFromTableCell(in: html) {
            return date
        }
        if let date = extractFirstDateFromFilename(in: html) {
            return date
        }
        throw NSError(domain: "PointFileDownloader", code: 1001, userInfo: [NSLocalizedDescriptionKey: "No valid date found"])
    }
    
    private func extractXLSXLinks(from html: String) -> [String] {
        let pattern = #"href=\"([^\"]+\.xlsx)\""#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex?.matches(in: html, range: range) ?? []
        return matches.compactMap {
            guard let r = Range($0.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }
    }
    
    private func extractDateFromTableCell(in html: String) -> Date? {
        let pattern = #"Data ostatniej modyfikacji:\s*</td>\s*<td>\s*<strong>([^<]+)</strong>"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex?.firstMatch(in: html, range: range),
              let dateRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let dateString = String(html[dateRange])
        return parseDate(from: dateString)
    }
    
    private func extractFirstDateFromFilename(in html: String) -> Date? {
        let pattern = #"\d{4}-\d{2}-\d{2}"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex?.firstMatch(in: html, range: range),
              let dateRange = Range(match.range, in: html) else {
            return nil
        }
        let dateString = String(html[dateRange])
        return parseDate(from: dateString)
    }
    
    private func parseDate(from string: String) -> Date? {
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "pl_PL")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = "dd.MM.yyyy HH:mm"
                return f
            }(),
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "pl_PL")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = "dd.MM.yyyy"
                return f
            }(),
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "pl_PL")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = "yyyy-MM-dd"
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}
