import AppKit
import WebKit

/// The zyx.tw pond as a live wallpaper: one window per screen at the desktop
/// level, under the desktop icons, that never takes a click. The koi follow
/// the cursor, which the app passes in, since the window ignores the mouse.
@MainActor
@Observable
final class PondModel {
    private static let key = "pond"
    /// A page with the pond but not the home's mark, which the koi would
    /// swim around even while hidden.
    private static let url = URL(string: "https://www.zyx.tw/privacy")!

    /// Only the pond, on pure black so the notch disappears into it: the
    /// page's header, mark and footer hide, and the TV frame comes off.
    private static let script = """
    (() => {
      const style = document.createElement("style");
      style.textContent = "html { background: #000 !important; } body { background: transparent !important; } body > :not(canvas) { visibility: hidden !important; }";
      document.documentElement.append(style);
      // remove() rewrites the attribute even when "tv" is gone, which would
      // wake the observer again, forever.
      const html = document.documentElement;
      const bare = () => html.classList.contains("tv") && html.classList.remove("tv");
      bare();
      new MutationObserver(bare).observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
    })();
    """

    private(set) var on = UserDefaults.standard.bool(forKey: key)
    private var windows: [NSWindow] = []
    private var cursor: Timer?
    private var last = NSPoint(x: -1, y: -1)
    private var screens: NSObjectProtocol?

    init() {
        if on { show() }
    }

    func set(_ value: Bool) {
        on = value
        UserDefaults.standard.set(value, forKey: Self.key)
        value ? show() : hide()
    }

    private func show() {
        hide()
        windows = NSScreen.screens.map(window)
        windows.forEach { $0.orderFront(nil) }
        cursor = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        }
    }

    private func hide() {
        cursor?.invalidate()
        cursor = nil
        if let screens { NotificationCenter.default.removeObserver(screens) }
        screens = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private func window(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        // ZYX_POND_FRONT=1 floats it over every window, to check it on a busy screen.
        let front = ProcessInfo.processInfo.environment["ZYX_POND_FRONT"] == "1"
        window.level = front ? .floating : NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black

        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        if ProcessInfo.processInfo.environment["ZYX_POND_LOG"] == "1" {
            config.userContentController.add(PondLog.shared, name: "log")
            config.userContentController.addUserScript(WKUserScript(source: """
            const send = (...a) => webkit.messageHandlers.log.postMessage(a.map(String).join(" "));
            const error = console.error; console.error = (...a) => { send("error", ...a); error(...a) };
            addEventListener("error", e => send("onerror", e.message, e.filename, e.lineno));
            addEventListener("unhandledrejection", e => send("rejection", e.reason && (e.reason.stack || e.reason)));
            setTimeout(() => send("gpu", !!navigator.gpu, "canvas", !!document.querySelector("canvas"), "reduced", matchMedia("(prefers-reduced-motion: reduce)").matches), 4000);
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
        web.autoresizingMask = [.width, .height]
        if ProcessInfo.processInfo.environment["ZYX_POND_LOG"] == "1" { web.navigationDelegate = PondLog.shared }
        web.load(URLRequest(url: Self.url))
        window.contentView = web
        return window
    }

    /// Hands the cursor to the page under it, as a pointer move.
    private func follow() {
        let point = NSEvent.mouseLocation
        guard point != last else { return }
        last = point
        for window in windows {
            guard window.frame.contains(point), let web = window.contentView as? WKWebView else { continue }
            let x = point.x - window.frame.minX
            let y = window.frame.maxY - point.y
            web.evaluateJavaScript(
                "window.dispatchEvent(new PointerEvent('pointermove', { clientX: \(x), clientY: \(y), pointerType: 'mouse' }))"
            )
        }
    }
}

/// With ZYX_POND_LOG=1: prints page errors, loads and the canvas state.
final class PondLog: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = PondLog()
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("pond: finished", webView.url?.absoluteString ?? ""); fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            webView.evaluateJavaScript("JSON.stringify({gpu: !!navigator.gpu, vis: document.visibilityState, focus: document.hasFocus(), reduced: matchMedia('(prefers-reduced-motion: reduce)').matches, canvas: (() => { const c = document.querySelector('canvas'); return c && [c.width, c.height, getComputedStyle(c).visibility, getComputedStyle(c).display] })()})") { result, error in
                print("pond: state", result ?? "", error ?? ""); fflush(stdout)
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { print("pond: failed", error); fflush(stdout) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { print("pond: failed early", error); fflush(stdout) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { print("pond: web process ended"); fflush(stdout) }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        print("pond:", message.body)
        fflush(stdout)
    }
}
