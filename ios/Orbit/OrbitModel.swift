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
    @Published var downloadMessage: String?
    let webView: WKWebView
    var coordinator: ConsoleCoordinator!
    private(set) var transport: RouterTransport?
    private(set) var endpoint: RouterEndpoint?
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
                    throw OrbitError.message("The router could not be reached securely. Join its Wi-Fi or enable Tailscale, then try again.")
                }
                guard attempt == currentAttempt else { return }
                var login = CredentialVault.Login(username:username, password:password)
                if password.isEmpty {
                    let existing = try await Task.detached { try CredentialVault.read(for:selected) }.value
                    guard let existing else { throw OrbitError.message("Enter your LuCI password for the first connection.") }
                    login = existing; username = existing.username
                }
                let cookies = try await connection.login(username:login.username,password:login.password)
                guard attempt == currentAttempt else { return }
                let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                for cookie in cookies { await cookieStore.setCookie(cookie) }
                if saveLogin && !password.isEmpty {
                    do { try CredentialVault.store(login,for:selected) }
                    catch { message = error.localizedDescription }
                }
                password = ""
                endpoint = selected
                UserDefaults.standard.set(selected.key,forKey:"orbit.endpoint")
                var destination = selected.console
                if let savedPath, let resumed = URL(string:savedPath,relativeTo:selected.origin), selected.contains(resumed) { destination = resumed }
                connected = true; locked = false; connectionSheet = false
                webView.load(URLRequest(url:destination))
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
