import Foundation
import Security
import CryptoKit

/// Exact endpoint + certificate binding. A changed certificate never receives a password.
final class RouterTransport: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let endpoint: RouterEndpoint
    let pin: String?
    private let lock = NSLock()
    private var observed: String?
    var observedFingerprint: String? { lock.lock(); defer { lock.unlock() }; return observed }
    init(endpoint: RouterEndpoint, pin: String?) { self.endpoint = endpoint; self.pin = pin }
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    static func fingerprint(_ trust: SecTrust) -> String? {
        guard let cert = SecTrustGetCertificateAtIndex(trust, 0) else { return nil }
        return SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format:"%02X", $0) }.joined(separator: ":")
    }
    func authenticate(_ challenge: URLAuthenticationChallenge, completion: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == endpoint.origin.host?.lowercased(),
              challenge.protectionSpace.port == (endpoint.origin.port ?? 443),
              let trust = challenge.protectionSpace.serverTrust, let fingerprint = Self.fingerprint(trust) else {
            completion(.cancelAuthenticationChallenge, nil); return
        }
        lock.lock(); observed = fingerprint; lock.unlock()
        guard fingerprint == pin else { completion(.cancelAuthenticationChallenge, nil); return }
        completion(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        authenticate(challenge, completion: completionHandler)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(endpoint.contains(request.url) ? request : nil)
    }
    func probe() async throws {
        var request = URLRequest(url:endpoint.console); request.httpMethod = "GET"
        let (_, response) = try await session.data(for:request)
        guard let http = response as? HTTPURLResponse, [200,302,403].contains(http.statusCode) else {
            throw OrbitError.message("The router answered, but its console is unavailable. Check that Field Console is installed.")
        }
    }
    func login(username: String, password: String) async throws -> [HTTPCookie] {
        var request = URLRequest(url:endpoint.console)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField:"Content-Type")
        request.httpBody = RouterEndpoint.form([("luci_username",username),("luci_password",password)])
        let (data,response) = try await session.data(for:request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data:data, encoding:.utf8), html.contains("id=\"ddk-app\""),
              let cookies = session.configuration.httpCookieStorage?.cookies(for:endpoint.console),
              cookies.contains(where: { $0.name == "sysauth_https" }) else {
            throw OrbitError.message("Sign-in did not open Field Console. Check the LuCI username and password, then try again.")
        }
        return cookies
    }
    func close() { session.invalidateAndCancel() }
}
