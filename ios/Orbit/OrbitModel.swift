import SwiftUI
import WebKit
import LocalAuthentication

@MainActor
final class OrbitModel: ObservableObject {
    @Published var address = UserDefaults.standard.string(forKey:"orbit.endpoint") ?? "https://192.168.8.1"
    @Published var username = "root"
    @Published var password = ""
    @Published var saveLogin = true
    @Published var connecting = false
    @Published var connected = false
    @Published var message: String?
    @Published var candidateFingerprint: String?
    @Published var connectionSheet = false
    @Published var sharedFile: SharedFile?
    @Published var locked = false
    @Published var obscured = false
    @Published var downloadMessage: String?
    @Published var pageLoading = false
    @Published var connectionProgress = "Contacting your router…"
    let webView: WKWebView
    var coordinator: ConsoleCoordinator!
    private(set) var transport: RouterTransport?
    private(set) var endpoint: RouterEndpoint?
    var openingNavigation: WKNavigation?
    private var savedPath: String?
    private var unlocking = false
    private var attempt = 0
    struct SharedFile: Identifiable { let id = UUID(); let url: URL }

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "DDKOrbit/0.1.0"
        webView = WKWebView(frame:.zero, configuration:configuration)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red:8/255,green:13/255,blue:25/255,alpha:1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.allowsBackForwardNavigationGestures = true
        coordinator = ConsoleCoordinator(model:self)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.configuration.userContentController.add(coordinator, name:"orbit")
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }
    func connect() {
        guard !connecting else { return }
        attempt += 1; let currentAttempt = attempt
        connecting = true; message = nil; candidateFingerprint = nil
        connectionProgress = "Contacting your router…"
        Task {
            defer { if attempt == currentAttempt { connecting = false } }
            do {
                let selected = try RouterEndpoint(address)
                address = selected.key
                let pin = UserDefaults.standard.string(forKey:"orbit.certificate." + selected.key)
                let connection = RouterTransport(endpoint:selected, pin:pin)
                transport?.close(); transport = connection
                do { try await connection.probe() }
                catch {
                    guard attempt == currentAttempt else { return }
                    if let fingerprint = connection.observedFingerprint, fingerprint != pin {
                        candidateFingerprint = fingerprint
                        message = pin == nil ? "Verify this router’s certificate before signing in." : "The router certificate has changed. Verify it before trusting this connection."
                        return
                    }
                    if let consoleError = error as? OrbitError { throw consoleError }
                    throw OrbitError.message("The router could not be reached securely. Join its Wi-Fi or enable Tailscale, then try again.")
                }
                guard attempt == currentAttempt else { return }
                var login = CredentialVault.Login(username:username, password:password)
                if password.isEmpty {
                    connectionProgress = "Unlock your saved sign-in…"
                    let existing = try await Task.detached { try CredentialVault.read(for:selected) }.value
                    guard let existing else { throw OrbitError.message("Enter your LuCI password for the first connection.") }
                    login = existing; username = existing.username
                }
                connectionProgress = "Signing in to your router…"
                let cookies = try await connection.login(username:login.username,password:login.password)
                guard attempt == currentAttempt else { return }
                let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                connectionProgress = "Opening your workspace…"
                // A real origin request starts WebKit's network process before
                // cookie transfer. An empty document does not establish it.
                endpoint = selected; connected = false; connectionSheet = false
                webView.load(URLRequest(url:selected.console,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15))
                for cookie in cookies {
                    try await CookieHandoff.perform { cookieStore.setCookie(cookie,completionHandler:$0) }
                }
                guard attempt == currentAttempt else { return }
                if saveLogin && !password.isEmpty {
                    do { try CredentialVault.store(login,for:selected) }
                    catch { message = error.localizedDescription }
                }
                password = ""
                endpoint = selected
                UserDefaults.standard.set(selected.key,forKey:"orbit.endpoint")
                var destination = selected.console
                if let savedPath, let resumed = URL(string:savedPath,relativeTo:selected.origin), selected.contains(resumed) { destination = resumed }
                connected = true; locked = false; connectionSheet = message != nil
                pageLoading = true
                openingNavigation = webView.load(URLRequest(url:destination))
            } catch {
                if attempt == currentAttempt { message = error.localizedDescription }
            }
        }
    }
    func trustCertificate() {
        guard let fingerprint = candidateFingerprint, let selected = try? RouterEndpoint(address),
              transport?.endpoint == selected, transport?.observedFingerprint == fingerprint else { return }
        // An explicit operator decision, never trust-on-network-error or an automatic replacement.
        UserDefaults.standard.set(fingerprint,forKey:"orbit.certificate." + selected.key)
        candidateFingerprint = nil; connect()
    }
    func cancelConnection() {
        attempt += 1; connecting = false; transport?.close(); candidateFingerprint = nil
        webView.stopLoading()
        message = "Connection cancelled. Existing router jobs were not stopped."
    }
    func reconnect() {
        if let endpoint, let url = webView.url, endpoint.contains(url), url.path.hasPrefix("/cgi-bin/luci/admin/ddk/") {
            savedPath = url.path + (url.query.map { "?" + $0 } ?? "") + (url.fragment.map { "#" + $0 } ?? "")
        }
        address = endpoint?.key ?? address
        connectionSheet = true
        connect()
    }
    func forgetLogin() {
        guard let selected = try? RouterEndpoint(address) else { return }
        CredentialVault.forget(selected)
        message = "Saved sign-in removed from this iPhone."
    }
    func disconnect() {
        attempt += 1; transport?.close(); transport = nil; connected = false; connecting = false
        webView.stopLoading(); savedPath = nil; password = ""; connectionSheet = false
        endpoint = nil; candidateFingerprint = nil; pageLoading = false; locked = false
        openingNavigation = nil
        // Replacing the document also stops its JavaScript polling after sign-out.
        webView.loadHTMLString("<!doctype html><html><body></body></html>",baseURL:nil)
        // Remove this app's router session cookie, retaining preferences and presets.
        let store = webView.configuration.websiteDataStore.httpCookieStore
        Task { for cookie in await store.allCookies() where cookie.name.hasPrefix("sysauth") { await store.deleteCookie(cookie) } }
    }
    func resume() {
        guard connected && locked && !unlocking else { return }
        unlocking = true
        Task {
            defer { unlocking = false }
            do {
                let success = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication,localizedReason:"Unlock your field workspace.")
                if success { locked = false }
            } catch { message = "Workspace is locked. Tap Unlock to continue." }
        }
    }
}

/// WebKit cookie callbacks have no error result. Bound the handoff so a stopped
/// website process cannot retain a sign-in task (and its password) indefinitely.
@MainActor
final class CookieHandoff {
    private var continuation: CheckedContinuation<Void,Error>?
    private var timer: Task<Void,Never>?
    private init(_ continuation:CheckedContinuation<Void,Error>) { self.continuation = continuation }
    private func finish(_ error:Error? = nil) {
        guard let completion = continuation else { return }
        continuation = nil; timer?.cancel(); timer = nil
        if let error { completion.resume(throwing:error) } else { completion.resume() }
    }
    static func perform(timeout:Duration = .seconds(15), install:(@escaping @MainActor ()->Void)->Void) async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            let handoff = CookieHandoff(continuation)
            handoff.timer = Task {
                do { try await Task.sleep(for:timeout) } catch { return }
                handoff.finish(OrbitError.message("The iPhone could not open the router session. Tap Connect to try again; router jobs are still running."))
            }
            install { handoff.finish() }
        }
    }
}
