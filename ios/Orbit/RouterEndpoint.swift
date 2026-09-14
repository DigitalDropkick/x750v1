import Foundation

struct RouterEndpoint: Equatable {
    let origin: URL
    init(_ text: String) throws {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port!) else {
            throw OrbitError.message("Enter an HTTPS router address, such as https://192.168.8.1, without a page path or password.")
        }
        var clean = URLComponents()
        clean.scheme = "https"; clean.host = host.lowercased(); clean.port = parts.port == 443 ? nil : parts.port
        guard let url = clean.url else { throw OrbitError.message("This router address is invalid.") }
        origin = url
    }
    var key: String { origin.absoluteString }
    var console: URL { origin.appendingPathComponent("cgi-bin/luci/admin/ddk/overview").appending(queryItems: [.init(name: "orbit", value: "1")]) }
    func contains(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == origin.host?.lowercased()
            && (url.port ?? 443) == (origin.port ?? 443) && url.user == nil && url.password == nil
    }
    static func form(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return fields.map { key, value in
            key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").data(using: .utf8)!
    }
}

enum OrbitError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
