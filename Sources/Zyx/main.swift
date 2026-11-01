import AppKit
import SwiftUI
import ZyxKit

/// Sizes measured from the system Sound menu (macOS 27), in points.
enum Metrics {
    static let width: CGFloat = 308
    static let corner: CGFloat = 16
    /// Rows and separators that span the menu sit this far inside its edge.
    static let edge: CGFloat = 5
    static let inset: CGFloat = 14
    static let row: CGFloat = 32
    static let icon: CGFloat = 26
    /// Gap from the menu bar to the top of the menu.
    static let drop: CGFloat = 6
}

/// The zyx toolkit in the menu bar: one panel, one row per tool. A panel,
/// not an NSMenu, so it matches the system Sound and Wi-Fi menus: the round
/// corners, the gray hover and the blue switch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let dopamine = DopamineModel()
    private lazy var panel = MenuPanel(content: MenuView(dopamine: dopamine, quit: { NSApp.terminate(nil) }))
    private var monitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let icon = Bundle.main.image(forResource: "MenuIcon")
        if let icon {
            // The PDF comes at its page size; the menu bar wants 18 pt high.
            icon.size = NSSize(width: 18 * icon.size.width / max(icon.size.height, 1), height: 18)
            icon.isTemplate = true
        }
        item.button?.image = icon ?? NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "zyx")
        item.button?.setAccessibilityLabel("zyx")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])

        if ProcessInfo.processInfo.environment["ZYX_OPEN_MENU"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.open() }
        }
    }

    @objc private func toggle() {
        panel.isVisible ? close() : open()
    }

    private func open() {
        guard let button = item.button, let bar = button.window else { return }
        dopamine.refresh()
        let anchor = bar.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.fit()
        let screen = bar.screen?.visibleFrame ?? .infinite
        let x = max(screen.minX + Metrics.edge, anchor.maxX - size.width)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.minY - Metrics.drop))
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)

        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.close()
            return nil
        }
        monitors = [outside, escape].compactMap { $0 }
    }

    private func close() {
        panel.orderOut(nil)
        item.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}

/// A borderless panel that takes key focus without activating the app, so
/// the switch draws in the accent color and hover works.
final class MenuPanel: NSPanel {
    private let host: NSHostingView<AnyView>

    init(content: some View) {
        host = NSHostingView(rootView: AnyView(content))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // The system menu material: translucent, it tints what is behind.
        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = Metrics.corner
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    /// Resizes the panel to its content and returns the size.
    func fit() -> NSSize {
        let size = NSSize(width: Metrics.width, height: host.fittingSize.height)
        setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        return size
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

struct MenuView: View {
    let dopamine: DopamineModel
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DopamineRow(model: dopamine)
            Divider()
                .padding(.horizontal, Metrics.inset)
                .padding(.vertical, 5)
            ActionRow(title: "Quit zyx", height: 22, action: quit) {
                Text("Quit zyx").font(.system(size: 13))
            }
        }
        .padding(.vertical, Metrics.edge)
        .frame(width: Metrics.width)
    }
}

/// The whole row is the switch, like Low Power in the system Battery menu:
/// the icon circle turns blue when Dopamine is on.
struct DopamineRow: View {
    let model: DopamineModel

    var body: some View {
        let on = model.on == true
        ActionRow(title: "Dopamine", height: model.error == nil ? Metrics.row : 40, action: {
            if let current = model.on, !model.busy { model.set(!current) }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .white : .primary)
                    .frame(width: Metrics.icon, height: Metrics.icon)
                    .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.secondary), in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dopamine").font(.system(size: 13))
                    if let error = model.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "on" : "off")
    }
}

/// A row with the system gray hover: it spans the menu less 5 pt each side,
/// with corners concentric to the menu's.
struct ActionRow<Content: View>: View {
    let title: String
    let height: CGFloat
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.inset - Metrics.edge)
                .frame(height: height)
                .background(
                    hover ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: Metrics.corner - Metrics.edge, style: .continuous)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .onHover { hover = $0 }
        .padding(.horizontal, Metrics.edge)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
