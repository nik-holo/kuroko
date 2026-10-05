import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WebLinkError: Error, CustomStringConvertible {
    case notALink
    case badResponse(Int)
    case tooLarge
    case noImageFound
    case notAnImage

    var description: String {
        switch self {
        case .notALink: return "file does not contain a web URL"
        case .badResponse(let code): return "server answered HTTP \(code)"
        case .tooLarge: return "download exceeds the size limit"
        case .noImageFound: return "page has no image to download"
        case .notAnImage: return "downloaded data is not an image"
        }
    }
}

/// Turns browser link files (`.webloc`, `.url`) and web URLs into image files.
///
/// Dragging an image out of Safari/Chrome often doesn't produce an image at all:
/// when the picture is wrapped in a link (Threads, Instagram, Dribbble…) macOS
/// writes a `.webloc` pointing at the page instead. This resolves such links:
/// a URL that serves an image directly is downloaded as-is; an HTML page is
/// scanned for its `og:image` / `twitter:image` / `image_src` and that is fetched.
enum WebLinkResolver {
    static let linkExtensions: Set<String> = ["webloc", "url"]
    static let maxBytes = 100 * 1_048_576
    static let timeout: TimeInterval = 30

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func isLinkFile(_ url: URL) -> Bool {
        linkExtensions.contains(url.pathExtension.lowercased())
    }

    /// Reads the URL out of a `.webloc` (plist) or `.url` (INI) file.
    static func url(fromLinkFile file: URL) -> URL? {
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let string = plist["URL"] as? String, let url = URL(string: string) {
            return url
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("url="), let url = URL(string: String(trimmed.dropFirst(4))) {
                return url
            }
        }
        return nil
    }

    /// Resolves a web URL to image bytes plus a suggested filename (no directory).
    static func fetchImage(from pageURL: URL) async throws -> (data: Data, filename: String) {
        let (data, response) = try await get(pageURL)
        if let image = sniffImage(data) {
            return (data, filename(forImageAt: response.url ?? pageURL, page: nil, type: image))
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let imageURL = imageURL(inHTML: html, base: response.url ?? pageURL) else {
            throw WebLinkError.noImageFound
        }
        let (imageData, imageResponse) = try await get(imageURL, referer: pageURL)
        guard let type = sniffImage(imageData) else { throw WebLinkError.notAnImage }
        return (imageData, filename(forImageAt: imageResponse.url ?? imageURL, page: pageURL, type: type))
    }

    /// Downloads the image behind `pageURL` into `directory`, avoiding name collisions.
    static func download(_ pageURL: URL, into directory: URL) async throws -> URL {
        let (data, name) = try await fetchImage(from: pageURL)
        let target = uniqueURL(in: directory, filename: name)
        try data.write(to: target, options: .atomic)
        return target
    }

    // MARK: HTTP

    private static func get(_ url: URL, referer: URL? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebLinkError.badResponse(0) }
        guard (200..<300).contains(http.statusCode) else { throw WebLinkError.badResponse(http.statusCode) }
        guard data.count <= maxBytes else { throw WebLinkError.tooLarge }
        return (data, http)
    }

    // MARK: HTML scraping

    /// First usable image reference in an HTML document, in order of preference.
    static func imageURL(inHTML html: String, base: URL) -> URL? {
        let head = String(html.prefix(2_000_000))
        let patterns = [
            #"<meta[^>]+property=["']og:image(?::secure_url|:url)?["'][^>]*>"#,
            #"<meta[^>]+name=["']og:image["'][^>]*>"#,
            #"<meta[^>]+name=["']twitter:image(?::src)?["'][^>]*>"#,
            #"<meta[^>]+property=["']twitter:image(?::src)?["'][^>]*>"#,
            #"<link[^>]+rel=["']image_src["'][^>]*>"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(head.startIndex..., in: head)
            for match in regex.matches(in: head, range: range) {
                guard let tagRange = Range(match.range, in: head) else { continue }
                let tag = String(head[tagRange])
                if let value = attribute("content", in: tag) ?? attribute("href", in: tag),
                   let url = URL(string: decodeEntities(value), relativeTo: base)?.absoluteURL,
                   ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    return url
                }
            }
        }
        return nil
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*([\"'])(.*?)\\1"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 2), in: tag) else { return nil }
        let value = tag[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&#39;", with: "'")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
    }

    // MARK: naming

    /// Checks the bytes really decode as an image and returns their type.
    static func sniffImage(_ data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier), type.conforms(to: .image) else { return nil }
        return type
    }

    /// A readable filename: for a page-embedded image, `<host> <post id>.<ext>`
    /// (e.g. `threads.com Dd0s3ZfjvaD.jpg`); for a direct image, its own name.
    static func filename(forImageAt imageURL: URL, page: URL?, type: UTType) -> String {
        let ext = type == .jpeg ? "jpg" : (type.preferredFilenameExtension ?? "img")
        var base: String
        if let page {
            let host = (page.host ?? "web").replacingOccurrences(of: "www.", with: "")
            let segments = page.pathComponents.filter { $0 != "/" && !$0.hasPrefix("@") && $0.lowercased() != "media" }
            let id = segments.last.map { String($0.prefix(40)) }
            base = [host, id].compactMap { $0 }.joined(separator: " ")
        } else {
            base = imageURL.deletingPathExtension().lastPathComponent
            if base.isEmpty || base == "/" { base = imageURL.host ?? "image" }
        }
        base = sanitize(base)
        return base.isEmpty ? "image.\(ext)" : "\(base).\(ext)"
    }

    private static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let cleaned = name.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) }
        return String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func uniqueURL(in directory: URL, filename: String) -> URL {
        let url = URL(fileURLWithPath: filename)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
