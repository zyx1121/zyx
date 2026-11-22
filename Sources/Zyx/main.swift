import AppKit
import ServiceManagement
import SwiftUI
import ZyxKit

/// zyx lives in the notch: no menu bar item. Its tools are rows in the
/// island, which opens on a click; see `Island`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dopamine = DopamineModel()
    private var island: Island?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Open at login, once: turning it off in System Settings sticks.
        let offered = "launchAtLoginOffered"
        if !UserDefaults.standard.bool(forKey: offered), Bundle.main.bundleURL.pathExtension == "app" {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: offered)
        }
        island = Island(dopamine: dopamine)
    }

    /// `zyx://done?…` from the Claude Code Stop hook.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let notice = Notice(url: url) { island?.show(notice) }
        }
    }
}

@MainActor
@Observable
final class DopamineModel {
    /// The system setting as last read; nil until read, or when unreadable.
    var on: Bool?
    var busy = false
    var error: String?

    func refresh() {
        on = Dopamine.isOn()
    }

    func set(_ value: Bool) {
        busy = true
        error = nil
        Task {
            let failure: String? = await Task.detached {
                do { try Dopamine.set(value); return nil } catch { return error.localizedDescription }
            }.value
            error = failure
            busy = false
            refresh()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
