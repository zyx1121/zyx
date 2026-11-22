import AppKit
import SwiftUI
import ZyxKit

/// Sizes of the island, in points.
private enum Shape {
    /// How much the island grows past the notch on hover.
    static let grow = CGSize(width: 80, height: 12)
    /// Clawd's pixels are as tall as twice their width, like a terminal
    /// cell's quarter blocks.
    static let clawdPixel = CGSize(width: 1.5, height: 3)
    static let clawdInset: CGFloat = 10
    /// Room around the grown island for the spring to overshoot into.
    static let slack = CGSize(width: 24, height: 12)
    /// The flare where the island meets the top edge, like the notch itself.
    static let flare: CGFloat = 6
    static let corner: CGFloat = 10
    static let hoverCorner: CGFloat = 14
}

/// A Dynamic Island around the notch: one borderless panel per notched
/// screen, over the menu bar, on every Space and beside full screen apps. At
/// rest it is a black shape the size of the notch, so it disappears into the
/// camera housing; under the cursor it grows with a spring and a tap on the
/// trackpad.
@MainActor
final class Island {
    private var islands: [Screen] = []
    private var layout: [NSRect] = []
    private var observer: NSObjectProtocol?
    private var monitors: [Any] = []

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
        islands = notches.map(Screen.init)
    }

    private func track() {
        let point = NSEvent.mouseLocation
        for island in islands {
            let hovering = Notch.hovers(point, notch: island.notch, grown: island.grown,
                                        hovering: island.state.hovering)
            guard hovering != island.state.hovering else { continue }
            if hovering {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            island.state.hovering = hovering
        }
    }
}

@MainActor
@Observable
private final class IslandState {
    var hovering = false
}

/// The island on one screen: the notch, its grown shape and the panel that
/// holds both, sized once to the largest the shape gets.
@MainActor
private struct Screen {
    let notch: NSRect
    let grown: NSRect
    let state = IslandState()
    let panel: NSPanel

    init(notch: NSRect) {
        self.notch = notch
        grown = Notch.grown(notch, by: Shape.grow)
        let frame = Notch.grown(grown, by: CGSize(width: Shape.slack.width + 2 * Shape.flare,
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
        let host = NSHostingView(rootView: IslandView(state: state, notch: notch.size))
        // The panel keeps one size; the content animates inside it.
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
    }
}

private struct IslandView: View {
    let state: IslandState
    let notch: CGSize

    var body: some View {
        let hovering = state.hovering
        let width = notch.width + (hovering ? Shape.grow.width : 0) + 2 * Shape.flare
        let height = notch.height + (hovering ? Shape.grow.height : 0)
        IslandShape(flare: Shape.flare, corner: hovering ? Shape.hoverCorner : Shape.corner)
            .fill(.black)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                // Clawd in the left wing, beside the camera.
                ClawdView(pixel: Shape.clawdPixel)
                    .padding(.leading, Shape.flare + Shape.clawdInset)
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6, anchor: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.38, dampingFraction: 0.68), value: hovering)
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
