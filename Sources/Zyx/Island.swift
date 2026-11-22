import AppKit
import SwiftUI
import ZyxKit

/// The frame for a Dynamic Island around the notch: one borderless panel per
/// notched screen, over the menu bar, on every Space and beside full screen
/// apps. For now it only outlines the camera housing, to check the geometry.
@MainActor
final class Island {
    private var panels: [NSPanel] = []
    private var layout: [NSRect] = []
    private var observer: NSObjectProtocol?

    init() {
        build()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.build() }
        }
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
        panels.forEach { $0.orderOut(nil) }
        panels = notches.map(Self.panel)
    }

    private static func panel(at rect: NSRect) -> NSPanel {
        let panel = IslandPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        // The status bar level is enough: measured above a full screen app.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        // A panel hides when its app deactivates; this app never activates.
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: Marker(size: rect.size))
        // The panel keeps one size; the content animates inside it.
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
        return panel
    }
}

/// A red outline on the notch, with its size in points.
private struct Marker: View {
    let size: CGSize

    var body: some View {
        ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                .strokeBorder(.red, lineWidth: 2)
            Text("\(Int(size.width)) × \(size.height, specifier: "%.1f") pt")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.red)
                .padding(.bottom, 3)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// AppKit pushes windows below the menu bar; in full screen that moved the
/// island under the camera band. The island stays where it is placed.
private final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
