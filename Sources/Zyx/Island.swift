import AppKit
import SwiftUI
import ZyxKit

/// Sizes of the island, in points.
private enum Shape {
    /// How much the island grows past the notch on hover.
    static let grow = CGSize(width: 80, height: 12)
    /// How much it grows to show a notice: a row under the camera.
    static let noticeGrow = CGSize(width: 180, height: 50)
    /// Clawd's pixels are as tall as twice their width, like a terminal
    /// cell's quarter blocks.
    static let clawdPixel = CGSize(width: 1.5, height: 3)
    static let noticeClawdPixel = CGSize(width: 2, height: 4)
    static let clawdInset: CGFloat = 10
    static let noticeInset: CGFloat = 18
    /// Room around the largest island for the spring to overshoot into.
    static let slack = CGSize(width: 24, height: 12)
    /// The flare where the island meets the top edge, like the notch itself.
    static let flare: CGFloat = 6
    static let corner: CGFloat = 10
    static let hoverCorner: CGFloat = 14
    static let noticeCorner: CGFloat = 22
    /// How long a notice stays when the cursor is not on it.
    static let noticeTime: TimeInterval = 6
}

/// A Dynamic Island around the notch: one borderless panel per notched
/// screen, over the menu bar, on every Space and beside full screen apps. At
/// rest it is a black shape the size of the notch, so it disappears into the
/// camera housing; under the cursor it grows with a spring and a tap on the
/// trackpad. A Claude Code session that finishes a turn opens it wider with
/// a notice; a click on the notice brings that session's tmux tab forward.
@MainActor
final class Island {
    private var islands: [Screen] = []
    private var layout: [NSRect] = []
    private var observer: NSObjectProtocol?
    private var monitors: [Any] = []
    private var dismiss: DispatchWorkItem?

    init() {
        build()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.build() }
        }
        // The panel ignores the mouse, so clicks reach the menu bar under its
        // margins; the cursor is watched instead. Mouse moves need no
        // Accessibility permission, unlike keys.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.track()
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    /// Shows a finished session, unless its tab is already on screen.
    func show(_ notice: Notice) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard notice.worthShowing(terminalInFront: front == Terminal.bundle) else { return }
        for island in islands { island.show(notice) }
        scheduleDismiss()
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
        islands = notches.map { Screen(notch: $0, open: { [weak self] notice in self?.open(notice) }) }
    }

    private func track() {
        let point = NSEvent.mouseLocation
        for island in islands {
            let state = island.state
            let hovering = Notch.hovers(point, notch: island.notch, grown: island.shown,
                                        hovering: state.hovering)
            guard hovering != state.hovering else { continue }
            if hovering {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            state.hovering = hovering
            // A notice stays while the cursor is on it, and leaves a moment
            // after the cursor does.
            if state.notice != nil {
                hovering ? dismiss?.cancel() : scheduleDismiss(after: 1.5)
            }
        }
    }

    private func scheduleDismiss(after delay: TimeInterval = Shape.noticeTime) {
        dismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.islands.forEach { $0.show(nil) } }
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func open(_ notice: Notice) {
        dismiss?.cancel()
        islands.forEach { $0.show(nil) }
        Terminal.focus(notice)
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
}

/// The island on one screen: the notch, its grown shapes and the panel that
/// holds them, sized once to the largest the shape gets.
@MainActor
private struct Screen {
    let notch: NSRect
    let grown: NSRect
    let noticed: NSRect
    let state = IslandState()
    let panel: NSPanel

    /// The island as it is drawn now, for hover.
    var shown: NSRect { state.notice == nil ? grown : noticed }

    init(notch: NSRect, open: @escaping @MainActor (Notice) -> Void) {
        self.notch = notch
        grown = Notch.grown(notch, by: Shape.grow)
        noticed = Notch.grown(notch, by: Shape.noticeGrow)
        let frame = Notch.grown(noticed, by: CGSize(width: Shape.slack.width + 2 * Shape.flare,
                                                    height: Shape.slack.height))
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
        let host = ClickHost(rootView: IslandView(state: state, notch: notch.size, open: open))
        // The panel keeps one size; the content animates inside it.
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
    }

    /// Shows a notice, or the plain island for nil. The panel takes clicks
    /// only while a notice is up, so the menu bar under it stays usable.
    func show(_ notice: Notice?) {
        state.notice = notice
        panel.ignoresMouseEvents = notice == nil
    }
}

/// Takes the first click even though the panel never activates the app.
private final class ClickHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct IslandView: View {
    let state: IslandState
    let notch: CGSize
    let open: @MainActor (Notice) -> Void

    var body: some View {
        let hovering = state.hovering
        let notice = state.notice
        let grow = notice != nil ? Shape.noticeGrow : hovering ? Shape.grow : .zero
        let corner = notice != nil ? Shape.noticeCorner : hovering ? Shape.hoverCorner : Shape.corner
        IslandShape(flare: Shape.flare, corner: corner)
            .fill(.black)
            .frame(width: notch.width + grow.width + 2 * Shape.flare, height: notch.height + grow.height)
            .overlay(alignment: .leading) {
                // Clawd in the left wing, beside the camera.
                ClawdView(pixel: Shape.clawdPixel)
                    .padding(.leading, Shape.flare + Shape.clawdInset)
                    .opacity(hovering && notice == nil ? 1 : 0)
                    .scaleEffect(hovering && notice == nil ? 1 : 0.6, anchor: .leading)
            }
            .overlay(alignment: .bottomLeading) {
                if let notice {
                    NoticeRow(notice: notice)
                        .padding(.leading, Shape.flare + Shape.noticeInset)
                        .padding(.trailing, Shape.flare + Shape.noticeInset)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if let notice { open(notice) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.38, dampingFraction: 0.68), value: hovering)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: notice)
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
