import XCTest
import WebKit
import CryptoKit
@testable import Orbit

/// Real HTTPS and WebKit on the simulator, against tests/router-fixture.py.
final class RouterIntegrationTests: XCTestCase {
    private let address = "https://127.0.0.1:18443"
    private let username = "orbit-test+operator"
    private let password = "test &+ unicode ü"

    private func verifiedTransport() async throws -> RouterTransport {
        let endpoint = try RouterEndpoint(address)
        let initial = RouterTransport(endpoint:endpoint,pin:nil)
        do { try await initial.probe(); XCTFail("Unknown certificate was accepted") }
        catch { /* First contact must require operator certificate verification. */ }
        let fingerprint = try XCTUnwrap(initial.observedFingerprint)
        XCTAssertEqual(fingerprint.split(separator:":").count,32)
        initial.close()
        let transport = RouterTransport(endpoint:endpoint,pin:fingerprint)
        try await transport.probe()
        return transport
    }

    func testCertificatePairingSignInAndAuthenticatedDownload() async throws {
        let transport = try await verifiedTransport()
        defer { transport.close() }
        let cookies = try await transport.login(username:username,password:password)
        XCTAssertTrue(cookies.contains { $0.name == "sysauth_https" && $0.isSecure })
        let url = try XCTUnwrap(URL(string:address+"/cgi-bin/luci/admin/ddk/download"))
        let (data,response) = try await transport.session.data(from:url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
        XCTAssertEqual(String(data:data,encoding:.utf8),"orbit native report\n")
    }

    func testWrongPasswordIsReported() async throws {
        let transport = try await verifiedTransport()
        defer { transport.close() }
        do { _ = try await transport.login(username:username,password:"wrong-test-input"); XCTFail("Wrong sign-in was accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Sign-in did not open")) }
    }

    func testChangedCertificateIsRejected() async throws {
        let transport = RouterTransport(endpoint:try RouterEndpoint(address),pin:"outdated-certificate")
        defer { transport.close() }
        do { try await transport.probe(); XCTFail("Changed certificate was accepted") }
        catch { XCTAssertNotNil(transport.observedFingerprint) }
    }

    func testExternalRedirectIsNotFollowed() async throws {
        let transport = try await verifiedTransport()
        defer { transport.close() }
        let url = try XCTUnwrap(URL(string:address+"/cgi-bin/luci/admin/ddk/redirect"))
        let (_,response) = try await transport.session.data(from:url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,302)
        XCTAssertEqual(response.url,url)
    }

    @MainActor
    private func waitUntil(_ description:String, condition:()->Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds:100_000_000) }
        guard condition() else {
            XCTFail(description)
            throw OrbitError.message(description)
        }
    }

    @MainActor
    func testNativeSessionReachesWebKitAndStreamsAllDownloadTypes() async throws {
        let model = OrbitModel()
        // Synthetic JavaScript clicks have no UIKit user gesture. The UI suite
        // separately tests real taps with the app's default popup preference.
        model.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        model.webView.frame = window.bounds
        window.addSubview(model.webView)
        defer {
            model.webView.removeFromSuperview()
            model.disconnect()
            UserDefaults.standard.removeObject(forKey:"orbit.endpoint")
            UserDefaults.standard.removeObject(forKey:"orbit.certificate."+address)
        }
        UserDefaults.standard.removeObject(forKey:"orbit.certificate."+address)
        model.address = address; model.username = username; model.password = password; model.saveLogin = false
        model.connect()
        try await waitUntil("First connection should request certificate verification") { !model.connecting }
        XCTAssertFalse(model.connected)
        XCTAssertNotNil(model.candidateFingerprint)
        model.trustCertificate()
        try await waitUntil("Verified connection should open WebKit") { model.connected && !model.pageLoading }
        XCTAssertFalse(model.connectionSheet)
        let heading = try await model.webView.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(heading,"Orbit test workspace")
        XCTAssertTrue(model.password.isEmpty)
        for (script, expected) in [
            ("document.querySelector('a[download]').click()", "orbit native report\n"),
            ("document.querySelector('form button').click()", "orbit POST case\n"),
            ("document.querySelector('#stream-export').click()", "large artifact"),
            ("document.querySelectorAll('button')[2].click()", "orbit blob report\n")
        ] {
            model.sharedFile = nil
            _ = try await model.webView.evaluateJavaScript(script + "; true")
            try await waitUntil("Download \(expected.trimmingCharacters(in:.whitespacesAndNewlines)) should stream; status: \(model.message ?? "none")") { model.sharedFile != nil }
            let file = try XCTUnwrap(model.sharedFile?.url)
            if expected == "large artifact" {
                let handle = try FileHandle(forReadingFrom:file)
                defer { try? handle.close() }
                var hash = SHA256(); var size = 0
                while let data = try handle.read(upToCount:1024*1024), !data.isEmpty {
                    size += data.count; hash.update(data:data)
                }
                XCTAssertEqual(size,17*1024*1024)
                XCTAssertEqual(hash.finalize().map { String(format:"%02x",$0) }.joined(),"e348a8d9bb235ffc4b93bc5899fdf5503cdb68ca743d12dd06afde10f44e3fc7")
            } else { XCTAssertEqual(try String(contentsOf:file,encoding:.utf8),expected) }
            XCTAssertFalse(model.connectionSheet,"A normal download should not show a connection failure")
            try FileManager.default.removeItem(at:file.deletingLastPathComponent())
        }
        _ = try await model.webView.evaluateJavaScript("window.webkit.messageHandlers.orbit.postMessage({type:'connection'}); true")
        try await waitUntil("Trusted console bridge should open connection settings") { model.connectionSheet }
    }
}
