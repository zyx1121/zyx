import AppKit
import SwiftUI
import ZyxKit

/// The zyx toolkit in the menu bar: a native NSMenu, one row per tool.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let dopamine = DopamineModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let icon = Bundle.main.image(forResource: "MenuIcon")
        icon?.isTemplate = true
        item.button?.image = icon ?? NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "zyx")
        item.button?.toolTip = "zyx"

        menu.delegate = self
        menu.autoenablesItems = false
        let row = NSMenuItem()
        let view = NSHostingView(rootView: DopamineRow(model: dopamine))
        view.frame.size = NSSize(width: 260, height: view.fittingSize.height)
        view.autoresizingMask = [.width]
        row.view = view
        menu.addItem(row)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit zyx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        dopamine.refresh()

        if ProcessInfo.processInfo.environment["ZYX_OPEN_MENU"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.item.button?.performClick(nil) }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        dopamine.refresh()
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

/// One row like the system Wi-Fi menu: icon circle, title, switch.
struct DopamineRow: View {
    let model: DopamineModel

    var body: some View {
        let on = model.on == true
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? .white : .primary)
                .frame(width: 26, height: 26)
                .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dopamine").font(.system(size: 13))
                if let error = model.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Toggle("Dopamine", isOn: Binding(get: { on }, set: { model.set($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(model.busy || model.on == nil)
        }
        .padding(.horizontal, 13)
        .frame(minWidth: 260, maxWidth: .infinity, minHeight: model.error == nil ? 32 : 40)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
