import AppKit
import SwiftUI
import ZyxKit

/// Sizes of the island, in points.
private enum Shape {
    /// How much the island grows past the notch on hover.
    static let grow = CGSize(width: 80, height: 12)
    /// How much it grows to show a notice: a row under the camera.
    static let noticeGrow = CGSize(width: 180, height: 50)
    /// How much it grows to show the tools: their rows under the camera.
    static let toolsGrow = CGSize(width: 180, height: 92)
    static let row: CGFloat = 34
    static let icon: CGFloat = 24
    /// Clawd's pixels are as tall as twice their width, like a terminal
    /// cell's quarter blocks.
    static let clawdPixel = CGSize(width: 1.5, height: 3)
    static let noticeClawdPixel = CGSize(width: 2, height: 4)
    static let clawdInset: CGFloat = 10
    static let inset: CGFloat = 18
    /// Room around the largest island for the spring to overshoot into.
    static let slack = CGSize(width: 24, height: 12)
    /// The flare where the island meets the top edge, like the notch itself.
    static let flare: CGFloat = 6
    static let corner: CGFloat = 10
    static let hoverCorner: CGFloat = 14
    static let openCorner: CGFloat = 22
    /// How long a notice stays when the cursor is not on it.
    static let noticeTime: TimeInterval = 6
    /// How long the island stays open after the cursor leaves it.
    static let linger: TimeInterval = 1.2
}

/// zyx itself: a Dynamic Island around the notch, with no menu bar item.
/// One borderless panel per notched screen, over the menu bar, on every
/// Space and beside full screen apps.
///
/// - At rest it is a black shape the size of the notch, so it disappears
///   into the camera housing.
/// - Under the cursor it grows with a spring and a tap on the trackpad, and
///   Clawd looks out of the left wing.
/// - A click opens it to the tools, one row each, and Quit.
/// - A Claude Code session that finishes a turn opens it with a notice; a
///   click on the notice brings that session's tmux tab forward.
@MainActor
final class Island {
    private let dopamine: DopamineModel
    private var islands: [Screen] = []
    private var layout: [NSRect] = []
    private var observer: NSObjectProtocol?
    private var monitors: [Any] = []
    private var dismiss: DispatchWorkItem?

    init(dopamine: DopamineModel) {
        self.dopamine = dopamine
        build()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.build() }
        }
        // The panel ignores the mouse at rest, so clicks reach the menu bar
        // under its margins; the cursor is watched instead. Mouse moves need
        // no Accessibility permission, unlike keys.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] event in
            self?.track()
            return event
        }
        // A click in another app closes the tools, like a menu.
        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        monitors = [global, local, outside].compactMap { $0 }
    }

    /// Shows a finished session, unless its tab is already on screen.
    func show(_ notice: Notice) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard notice.worthShowing(terminalInFront: front == Terminal.bundle) else { return }
        for island in islands {
            island.state.tools = false
            island.state.notice = notice
            island.update()
        }
        schedule(after: Shape.noticeTime)
    }

    /// Rebuilds only when a notch moved: brightness changes post this
    /// notification too.
    private func build() {
        let notches = NSScreen.screens.compactMap { screen in
            Notch.rect(frame: screen.frame, left: screen.auxiliaryTopLeftArea,
                       right: screen.auxiliaryTopRightArea, top: screen.safeAreaInsets.top)
        }
        guard notches != layout else { return }
        layout = notches
        islands.forEach { $0.panel.orderOut(nil) }
        islands = notches.map { notch in
            Screen(notch: notch, dopamine: dopamine) { [weak self] in self?.tap() }
        }
    }

    private func track() {
        let point = NSEvent.mouseLocation
        for island in islands {
            let state = island.state
            let hovering = Notch.hovers(point, notch: island.notch, grown: island.shown,
                                        hovering: state.hovering)
            guard hovering != state.hovering else { continue }
            if hovering, !state.open {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            state.hovering = hovering
            island.update()
            // An open island stays while the cursor is on it, and closes a
            // moment after the cursor leaves.
            if state.open {
                hovering ? dismiss?.cancel() : schedule(after: Shape.linger)
            }
        }
    }

    /// A click on the island: a notice opens its session, anything else
    /// opens or closes the tools.
    private func tap() {
        if let notice = islands.lazy.compactMap(\.state.notice).first {
            close()
            Terminal.focus(notice)
            return
        }
        let opening = !(islands.first?.state.tools ?? false)
        if opening { dopamine.refresh() }
        dismiss?.cancel()
        for island in islands {
            island.state.tools = opening
            island.update()
        }
    }

    private func close() {
        dismiss?.cancel()
        for island in islands where island.state.open {
            island.state.notice = nil
            island.state.tools = false
            island.update()
        }
    }

    private func schedule(after delay: TimeInterval) {
        dismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.close() }
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// The terminal that runs tmux with the Claude Code sessions.
private enum Terminal {
    static let bundle = "com.mitchellh.ghostty"

    /// Selects the notice's tmux window and pane, then brings the terminal
    /// to the front.
    static func focus(_ notice: Notice) {
        let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        if let tmux {
            for arguments in notice.jump {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tmux)
                process.arguments = arguments
                try? process.run()
                process.waitUntilExit()
            }
        }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.activate()
    }
}

@MainActor
@Observable
private final class IslandState {
    var hovering = false
    var notice: Notice?
    var tools = false

    /// Open: showing a notice or the tools, not just grown under the cursor.
    var open: Bool { notice != nil || tools }
}

/// The island on one screen: the notch, its grown shapes and the panel that
/// holds them, sized once to the largest the shape gets.
@MainActor
private struct Screen {
    let notch: NSRect
    let grown: NSRect
    let noticed: NSRect
    let tooled: NSRect
    let state = IslandState()
    let panel: NSPanel

    /// The island as it is drawn now, for hover.
    var shown: NSRect { state.tools ? tooled : state.notice != nil ? noticed : grown }

    init(notch: NSRect, dopamine: DopamineModel, tap: @escaping @MainActor () -> Void) {
        self.notch = notch
        grown = Notch.grown(notch, by: Shape.grow)
        noticed = Notch.grown(notch, by: Shape.noticeGrow)
        tooled = Notch.grown(notch, by: Shape.toolsGrow)
        let largest = CGSize(width: max(Shape.noticeGrow.width, Shape.toolsGrow.width),
                             height: max(Shape.noticeGrow.height, Shape.toolsGrow.height))
        let frame = Notch.grown(Notch.grown(notch, by: largest),
                                by: CGSize(width: Shape.slack.width + 2 * Shape.flare, height: Shape.slack.height))
        panel = IslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        // Above the status bar: at its level, macOS 27 draws its own notch
        // layer over the island when the cursor reaches the notch.
        panel.level = .statusBar + 8
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        // A panel hides when its app deactivates; this app never activates.
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        let host = ClickHost(rootView: IslandView(state: state, notch: notch.size, dopamine: dopamine, tap: tap))
        // The panel keeps one size; the content animates inside it.
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
    }

    /// The panel takes clicks only while the island is under the cursor or
    /// open, so the menu bar beside the notch stays usable.
    func update() {
        panel.ignoresMouseEvents = !(state.hovering || state.open)
    }
}

/// Takes the first click even though the panel never activates the app, and
/// tracks the cursor while the app is inactive, which it always is, so the
/// rows' hover works.
private final class ClickHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(where: { $0.owner === self && $0.options.contains(.activeAlways) }) {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect,
                                                                   .mouseEnteredAndExited, .mouseMoved],
                                           owner: self))
        }
    }
}

private struct IslandView: View {
    let state: IslandState
    let notch: CGSize
    let dopamine: DopamineModel
    let tap: @MainActor () -> Void

    var body: some View {
        let hovering = state.hovering
        let notice = state.notice
        let tools = state.tools
        let grow = tools ? Shape.toolsGrow : notice != nil ? Shape.noticeGrow : hovering ? Shape.grow : .zero
        let corner = state.open ? Shape.openCorner : hovering ? Shape.hoverCorner : Shape.corner
        let peek = hovering && !state.open
        IslandShape(flare: Shape.flare, corner: corner)
            .fill(.black)
            .frame(width: notch.width + grow.width + 2 * Shape.flare, height: notch.height + grow.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .overlay(alignment: .leading) {
                // Clawd in the left wing, beside the camera.
                ClawdView(pixel: Shape.clawdPixel)
                    .padding(.leading, Shape.flare + Shape.clawdInset)
                    .frame(height: notch.height + (peek ? Shape.grow.height : 0), alignment: .center)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(peek ? 1 : 0)
                    .scaleEffect(peek ? 1 : 0.6, anchor: .leading)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                Group {
                    if let notice {
                        NoticeRow(notice: notice)
                            .allowsHitTesting(false)
                    } else if tools {
                        ToolRows(dopamine: dopamine)
                    }
                }
                .padding(.horizontal, Shape.flare + Shape.inset - 8)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.38, dampingFraction: 0.68), value: hovering)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: notice)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: tools)
    }
}

/// Clawd, the session name and the first line of its last reply.
private struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        HStack(spacing: 12) {
            ClawdView(pixel: Shape.noticeClawdPixel)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(notice.message.isEmpty ? "Done" : notice.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }
}

/// The tools, one row each, then Quit.
private struct ToolRows: View {
    let dopamine: DopamineModel

    var body: some View {
        VStack(spacing: 0) {
            ToolRow(title: "Dopamine", symbol: "bolt.fill", on: dopamine.on == true, detail: dopamine.error) {
                if let current = dopamine.on, !dopamine.busy { dopamine.set(!current) }
            }
            ToolRow(title: "Quit zyx", symbol: "power", on: nil, detail: nil) {
                NSApp.terminate(nil)
            }
        }
    }
}

/// A whole row is the switch, as in the system menus: the icon circle turns
/// blue when the tool is on. `on` is nil for an action, not a switch.
private struct ToolRow: View {
    let title: String
    let symbol: String
    let on: Bool?
    let detail: String?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Shape.icon, height: Shape.icon)
                    .background(on == true ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.white.opacity(0.14)),
                                in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13)).foregroundStyle(.white)
                    if let detail {
                        Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Shape.row)
            .background(hover ? AnyShapeStyle(.white.opacity(0.1)) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(on.map { $0 ? "on" : "off" } ?? "")
    }
}

/// The notch outline: flared into the top edge, round at the bottom.
private struct IslandShape: SwiftUI.Shape {
    var flare: CGFloat
    var corner: CGFloat

    var animatableData: CGFloat {
        get { corner }
        set { corner = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let corner = min(corner, rect.height - flare, (rect.width - 2 * flare) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + flare, y: rect.minY + flare),
                          control: CGPoint(x: rect.minX + flare, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + flare, y: rect.maxY - corner))
        path.addQuadCurve(to: CGPoint(x: rect.minX + flare + corner, y: rect.maxY),
                          control: CGPoint(x: rect.minX + flare, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - flare - corner, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - flare, y: rect.maxY - corner),
                          control: CGPoint(x: rect.maxX - flare, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - flare, y: rect.minY + flare))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - flare, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// AppKit pushes windows below the menu bar; in full screen that moved the
/// island under the camera band. The island stays where it is placed.
private final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Clawd drawn from its block characters: one path of pixels in the Claude
/// Code orange.
private struct ClawdView: View {
    let pixel: CGSize
    private static let grid = Clawd.pixels()
    private static let color = Color(red: Double(Clawd.rgb.red) / 255,
                                     green: Double(Clawd.rgb.green) / 255,
                                     blue: Double(Clawd.rgb.blue) / 255)

    var body: some View {
        let grid = Self.grid
        Path { path in
            for (y, row) in grid.enumerated() {
                for (x, on) in row.enumerated() where on {
                    path.addRect(CGRect(x: CGFloat(x) * pixel.width, y: CGFloat(y) * pixel.height,
                                        width: pixel.width, height: pixel.height))
                }
            }
        }
        .fill(Self.color)
        .frame(width: CGFloat(grid[0].count) * pixel.width, height: CGFloat(grid.count) * pixel.height)
    }
}
