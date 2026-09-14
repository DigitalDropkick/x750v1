import SwiftUI
import WebKit

struct ConsoleWebView: UIViewRepresentable {
    let model: OrbitModel
    func makeUIView(context:Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView:WKWebView,context:Context) {}
}

@MainActor
final class ConsoleCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    weak var model: OrbitModel?
    private var children: [WKWebView] = []
    private var downloads: [ObjectIdentifier:URL] = [:]
    init(model:OrbitModel) { self.model = model }
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        guard let model, message.frameInfo.isMainFrame,
              model.endpoint?.contains(message.frameInfo.request.url) == true,
              message.frameInfo.request.url?.path.hasPrefix("/cgi-bin/luci/admin/ddk/") == true,
              let body = message.body as? [String:String] else { return }
        switch body["type"] {
        case "connection": model.connectionSheet = true
        case "reconnect": model.reconnect()
        default: break
        }
    }
    func webView(_ webView:WKWebView,didReceive challenge:URLAuthenticationChallenge,
                 completionHandler:@escaping (URLSession.AuthChallengeDisposition,URLCredential?) -> Void) {
        guard let transport = model?.transport else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        transport.authenticate(challenge,completion:completionHandler)
    }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let allowed = model?.endpoint?.contains(url) == true
        let ownBlob = url.scheme == "blob" && model?.endpoint?.contains(URL(string:String(url.absoluteString.dropFirst(5)))) == true
        let emptyWorkspace = url.absoluteString == "about:blank" && webView === model?.webView && model?.connected == false
        guard allowed || ownBlob || emptyWorkspace else {
            if action.navigationType == .linkActivated && action.targetFrame?.isMainFrame != false {
                model?.message = "This link leaves the router. Open external websites separately in Safari."
                model?.connectionSheet = true
            }
            decisionHandler(.cancel); return
        }
        decisionHandler(action.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView:WKWebView,decidePolicyFor response:WKNavigationResponse,decisionHandler:@escaping(WKNavigationResponsePolicy)->Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField:"Content-Disposition") ?? ""
        decisionHandler(!response.canShowMIMEType || disposition.lowercased().contains("attachment") ? .download : .allow)
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { failed(error) }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) { failed(error) }
    private func failed(_ error:Error) {
        let failure = error as NSError
        // WebKit interrupts page navigation when its response becomes a download.
        if (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled)
            || (failure.domain == "WebKitErrorDomain" && failure.code == 102) { return }
        model?.pageLoading = false
        model?.message = "The console connection was interrupted. Reconnect to resume your router workspace."
        model?.connectionSheet = true
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        guard webView === model?.webView, model?.connected == true else { return }
        // A bootstrap page may finish just after the authenticated navigation
        // starts. Only that final navigation may reveal the workspace.
        if let opening = model?.openingNavigation, navigation !== opening { return }
        model?.openingNavigation = nil
        model?.pageLoading = false
        guard webView.url?.path.hasPrefix("/cgi-bin/luci/admin/ddk/") == true else { return }
        webView.evaluateJavaScript("Boolean(document.getElementById('ddk-app'))") { [weak self] result,_ in
            if result as? Bool == false {
                self?.model?.message = "Your router session needs a fresh sign-in. Reconnect to continue."
                self?.model?.connectionSheet = true
            }
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) {
        model?.message = "iOS closed the console view to recover memory. Reconnect to resume your jobs."
        model?.connectionSheet = true
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,
                 for action:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        // Retain the original WebKit navigation, including POST bodies and blob downloads.
        guard action.targetFrame == nil else { return nil }
        let child = WKWebView(frame:.zero,configuration:configuration)
        child.navigationDelegate = self; child.uiDelegate = self
        children.append(child); return child
    }
    func webViewDidClose(_ webView:WKWebView) { children.removeAll { $0 === webView } }
    func webView(_ webView:WKWebView,navigationAction:WKNavigationAction,didBecome download:WKDownload) { download.delegate = self }
    func webView(_ webView:WKWebView,navigationResponse:WKNavigationResponse,didBecome download:WKDownload) { download.delegate = self }
    func download(_ download:WKDownload,decideDestinationUsing response:URLResponse,suggestedFilename:String,
                  completionHandler:@escaping(URL?)->Void) {
        let name = URL(fileURLWithPath:suggestedFilename).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { completionHandler(nil); return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Orbit-"+UUID().uuidString,isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:directory.path)
            let target = directory.appendingPathComponent(name)
            downloads[ObjectIdentifier(download)] = target
            model?.downloadMessage = "Downloading \(name)…"
            completionHandler(target)
        } catch {
            model?.message = "iPhone storage could not accept this download. Free space and try again; the original remains on the router."
            model?.connectionSheet = true
            completionHandler(nil)
        }
    }
    func downloadDidFinish(_ download:WKDownload) {
        model?.downloadMessage = nil
        if let url = downloads.removeValue(forKey:ObjectIdentifier(download)) { model?.sharedFile = .init(url:url) }
        children.removeAll { $0 === download.webView }
    }
    func download(_ download:WKDownload,didFailWithError error:Error,resumeData:Data?) {
        model?.downloadMessage = nil
        if let url = downloads.removeValue(forKey:ObjectIdentifier(download)) { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
        model?.message = "Download did not finish. The original file remains on the router; reconnect and try again."
        model?.connectionSheet = true
        children.removeAll { $0 === download.webView }
    }
    func download(_ download:WKDownload,didReceive challenge:URLAuthenticationChallenge,
                  completionHandler:@escaping(URLSession.AuthChallengeDisposition,URLCredential?)->Void) {
        guard let transport = model?.transport else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        transport.authenticate(challenge,completion:completionHandler)
    }
    func download(_ download:WKDownload,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,
                  decisionHandler:@escaping(WKDownload.RedirectPolicy)->Void) {
        decisionHandler(model?.endpoint?.contains(request.url) == true ? .allow : .cancel)
    }
    private func present(_ alert:UIAlertController) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var presenter = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let next = presenter?.presentedViewController { presenter = next }
        presenter?.present(alert,animated:true)
    }
    func webView(_ webView:WKWebView,runJavaScriptConfirmPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,
                 completionHandler:@escaping(Bool)->Void) {
        guard model?.endpoint?.contains(frame.request.url) == true else { completionHandler(false); return }
        let alert = UIAlertController(title:"Confirm operation",message:message,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"Cancel",style:.cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title:"Continue",style:.default) { _ in completionHandler(true) })
        present(alert)
    }
    func webView(_ webView:WKWebView,runJavaScriptAlertPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,
                 completionHandler:@escaping()->Void) {
        let alert = UIAlertController(title:"Field Console",message:message,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"OK",style:.default) { _ in completionHandler() }); present(alert)
    }
}

struct FileShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context:Context)->UIActivityViewController {
        let controller = UIActivityViewController(activityItems:[url],applicationActivities:nil)
        controller.completionWithItemsHandler = { _,_,_,_ in try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
        return controller
    }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}
