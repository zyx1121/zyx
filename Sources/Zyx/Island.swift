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
    static let toolsGrow = CGSize(width: 180, height: 126)
    static let row: CGFloat = 34
    static let icon: CGFloat = 24
    static let beanPixel: CGFloat = 1.5
    static let beanInset: CGFloat = 10
    /// The most agents the island lists at once.
    static let maxAgents = 6
    /// How much it grows to list the agents: a row each under the camera.
    static func rosterGrow(_ count: Int) -> CGSize {
        CGSize(width: 180, height: CGFloat(min(count, maxAgents)) * row + 24)
    }
    static let inset: CGFloat = 18
    /// The space under the last row.
    static let rowsBottom: CGFloat = 10
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
///   lists the running Claude Code sessions: each one a Bean in its own
///   color and outfit, its tab title and its status. A click on one brings
///   its tmux tab forward.
/// - A click opens it to the tools, one row each, and Quit.
/// - A Claude Code session that finishes a turn opens it with a notice; a
///   click on the notice brings that session's tmux tab forward.
@MainActor
final class Island {
    private let dopamine: DopamineModel
    private let stick: StickModel
    private var islands: [Screen] = []
    private var layout: [NSRect] = []
    private var observer: NSObjectProtocol?
    private var monitors: [Any] = []
    private var dismiss: DispatchWorkItem?
    private var settle: DispatchWorkItem?
    /// Reads the sessions every second, to list them and to see one start
    /// waiting for the person.
    private var poll: Timer?
    /// The tab titles as last read from tmux: read while the cursor is on
    /// the island, or when a session is new or starts waiting, not every
    /// second.
    private var titles: [String: String] = [:]
    private var waiting: Set<String> = []

    init(dopamine: DopamineModel, stick: StickModel) {
        self.dopamine = dopamine
        self.stick = stick
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
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
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

    /// An agent ran a command through stickd: the island shows which agent
    /// and what it does, for a moment, so a person sees who drives the Mac.
    /// `session` is the pid of the Claude Code session that sent it.
    func agentActed(_ command: String, session: Int32?) {
        guard let action = Agent.action(command) else { return }
        settle?.cancel()
        let agent = islands.first?.state.agents.first { $0.pid == session }
            ?? session.flatMap { pid in name(Agent.load()).first { $0.pid == pid } }
        let acting = Acting(agent: agent, action: action)
        for island in islands where island.state.acting != acting { island.state.acting = acting }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.islands.forEach { $0.state.acting = nil } }
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
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
            Screen(notch: notch, dopamine: dopamine, stick: stick,
                   tap: { [weak self] in self?.tap() }, open: { Terminal.focus(pane: $0.pane) })
        }
    }

    private func track() {
        let point = NSEvent.mouseLocation
        for island in islands {
            let state = island.state
            let hovering = Notch.hovers(point, notch: island.notch, grown: island.shown,
                                        hovering: state.hovering)
            let pointed = hovering ? island.agent(at: point)?.id : nil
            if pointed != state.pointed { state.pointed = pointed }
            guard hovering != state.hovering else { continue }
            if hovering, !state.open {
                refreshAgents()
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

    /// Reads the sessions; a session that starts waiting for the person
    /// opens the island with a notice, like a finished one.
    private func tick() {
        let agents = Agent.load()
        let nowWaiting = Set(agents.filter(\.status.isWaiting).map(\.id))
        let started = agents.filter { $0.status.isWaiting && !waiting.contains($0.id) }
        waiting = nowWaiting
        let unnamed = agents.contains { $0.pane.map { titles[$0] == nil } ?? false }
        if unnamed || !started.isEmpty || islands.contains(where: \.state.hovering) { titles = Terminal.titles() }
        publish(name(agents))
        for agent in name(started) {
            guard let pane = agent.pane else { continue }
            show(Notice(pane: pane, title: agent.name, message: agent.status.label,
                        active: Terminal.isActive(pane: pane)))
        }
    }

    /// Reads the running sessions with fresh tab titles.
    private func refreshAgents() {
        titles = Terminal.titles()
        publish(name(Agent.load()))
    }

    private func publish(_ agents: [Agent]) {
        for island in islands where island.state.agents != agents {
            island.state.agents = agents
        }
    }

    /// Names each session by its tmux tab title, when it has one.
    private func name(_ agents: [Agent]) -> [Agent] {
        agents.map { agent in
            var agent = agent
            if let pane = agent.pane, let title = titles[pane], !title.isEmpty { agent.name = title }
            return agent
        }
    }

    /// A click on the island: a notice opens its session, anything else
    /// opens or closes the tools.
    private func tap() {
        if let notice = islands.lazy.compactMap(\.state.notice).first {
            close()
            Terminal.focus(pane: notice.pane)
            return
        }
        let opening = !(islands.first?.state.tools ?? false)
        if opening {
            dopamine.refresh()
            stick.refresh()
        }
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
    private static let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Selects the pane's tmux window and pane, then brings the terminal to
    /// the front.
    static func focus(pane: String?) {
        if let pane {
            for arguments in Notice.jump(to: pane) { _ = run(arguments) }
        }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.activate()
    }

    /// Whether the pane is on screen: its window is the active one in an
    /// attached tmux session.
    static func isActive(pane: String) -> Bool {
        run(["display", "-p", "-t", pane, "#{&&:#{window_active},#{session_attached}}"])
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// Each pane's tab title, which the status line keeps in `@cc_title`.
    static func titles() -> [String: String] {
        let lines = run(["list-panes", "-a", "-F", "#{pane_id}\t#{@cc_title}"]).split(separator: "\n")
        return Dictionary(lines.compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }, uniquingKeysWith: { first, _ in first })
    }

    private static func run(_ arguments: [String]) -> String {
        guard let tmux else { return "" }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// An agent driving the Mac: which one, when known, and what it does.
private struct Acting: Equatable {
    let agent: Agent?
    let action: String
}

@MainActor
@Observable
private final class IslandState {
    var hovering = false
    var notice: Notice?
    var tools = false
    /// An agent is driving the Mac through stickd.
    var acting: Acting?
    /// The running Claude Code sessions, read when the cursor arrives.
    var agents: [Agent] = []

    /// The agent row under the cursor. The island tracks the cursor itself:
    /// SwiftUI's hover in a panel of an inactive app lags a row behind.
    var pointed: String?

    /// Listing the agents: under the cursor, not open, and some are running.
    var roster: Bool { hovering && !open && !agents.isEmpty }

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
    var shown: NSRect {
        state.tools ? tooled : state.notice != nil ? noticed
            : state.roster ? Notch.grown(notch, by: Shape.rosterGrow(state.agents.count)) : grown
    }

    init(notch: NSRect, dopamine: DopamineModel, stick: StickModel, tap: @escaping @MainActor () -> Void,
         open: @escaping @MainActor (Agent) -> Void) {
        self.notch = notch
        grown = Notch.grown(notch, by: Shape.grow)
        noticed = Notch.grown(notch, by: Shape.noticeGrow)
        tooled = Notch.grown(notch, by: Shape.toolsGrow)
        let sizes = [Shape.noticeGrow, Shape.toolsGrow, Shape.rosterGrow(Shape.maxAgents)]
        let largest = CGSize(width: sizes.map(\.width).max()!, height: sizes.map(\.height).max()!)
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
        let host = ClickHost(rootView: IslandView(state: state, notch: notch.size, dopamine: dopamine,
                                                  stick: stick, tap: tap, open: open))
        // The panel keeps one size; the content animates inside it.
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
    }

    /// The agent whose row is under `point`, in screen coordinates. The rows
    /// sit at the bottom of the island, `Shape.row` tall each.
    func agent(at point: NSPoint) -> Agent? {
        guard state.roster else { return nil }
        let agents = Array(state.agents.prefix(Shape.maxAgents))
        let island = Notch.grown(notch, by: Shape.rosterGrow(agents.count))
        let bottom = island.minY + Shape.rowsBottom
        guard island.insetBy(dx: Shape.flare, dy: 0).contains(point), point.y >= bottom else { return nil }
        let fromBottom = Int((point.y - bottom) / Shape.row)
        return fromBottom < agents.count ? agents[agents.count - 1 - fromBottom] : nil
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
    let stick: StickModel
    let tap: @MainActor () -> Void
    let open: @MainActor (Agent) -> Void

    var body: some View {
        let hovering = state.hovering
        let notice = state.notice
        let tools = state.tools
        let roster = state.roster
        let acting = notice == nil && !tools && !roster ? state.acting : nil
        let grow = tools ? Shape.toolsGrow : notice != nil || acting != nil ? Shape.noticeGrow
            : roster ? Shape.rosterGrow(state.agents.count) : hovering ? Shape.grow : .zero
        let corner = state.open || roster || acting != nil ? Shape.openCorner
            : hovering ? Shape.hoverCorner : Shape.corner
        let peek = hovering && !state.open && !roster
        IslandShape(flare: Shape.flare, corner: corner)
            .fill(.black)
            .frame(width: notch.width + grow.width + 2 * Shape.flare, height: notch.height + grow.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .overlay(alignment: .leading) {
                // Bean in the left wing, beside the camera.
                BeanView(seed: nil, pixel: Shape.beanPixel)
                    .padding(.leading, Shape.flare + Shape.beanInset)
                    .frame(height: notch.height + (peek ? Shape.grow.height : 0), alignment: .center)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(peek ? 1 : 0)
                    .scaleEffect(peek ? 1 : 0.6, anchor: .leading)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                Group {
                    if let notice {
                        NoticeRow(notice: notice, agents: state.agents)
                            .allowsHitTesting(false)
                    } else if tools {
                        ToolRows(dopamine: dopamine, stick: stick)
                    } else if roster {
                        AgentRows(agents: state.agents, pointed: state.pointed, open: open)
                    } else if let acting {
                        ActingRow(acting: acting)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, Shape.flare + Shape.inset - 8)
                .padding(.bottom, Shape.rowsBottom)
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.38, dampingFraction: 0.68), value: hovering)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: notice)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: tools)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: roster)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: acting)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: state.agents.count)
    }
}

/// The session's Bean, its name and the first line of its last reply.
private struct NoticeRow: View {
    let notice: Notice
    let agents: [Agent]

    var body: some View {
        HStack(spacing: 12) {
            BeanView(seed: agents.first { $0.pane == notice.pane }?.id ?? notice.pane,
                     pixel: Shape.beanPixel)
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

/// The agent driving the Mac and what it does, while stickd runs its
/// commands.
private struct ActingRow: View {
    let acting: Acting

    var body: some View {
        HStack(spacing: 12) {
            BeanView(seed: acting.agent?.id ?? "", pixel: Shape.beanPixel)
            VStack(alignment: .leading, spacing: 2) {
                Text(acting.agent?.name ?? "An agent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(acting.action)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }
}

/// The running sessions, one row each: Bean, the tab title and the status.
private struct AgentRows: View {
    let agents: [Agent]
    let pointed: String?
    let open: @MainActor (Agent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(agents.prefix(Shape.maxAgents)) { agent in
                AgentRow(agent: agent, hover: agent.id == pointed) { open(agent) }
            }
        }
    }
}

private struct AgentRow: View {
    let agent: Agent
    let hover: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                BeanView(seed: agent.id, pixel: Shape.beanPixel)
                Text(agent.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusLabel(agent: agent)
            }
            .padding(.horizontal, 8)
            .frame(height: Shape.row)
            .background(hover ? AnyShapeStyle(.white.opacity(0.1)) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(agent.name)
        .accessibilityValue(agent.status.label)
    }
}

/// A dot, a word and how long it has held: the dot pulses green while the
/// session works and yellow while it waits for the person.
private struct StatusLabel: View {
    let agent: Agent
    @State private var pulse = false

    var body: some View {
        let status = agent.status
        let waiting = status.isWaiting
        let moving = status == .working || waiting
        HStack(spacing: 5) {
            Circle()
                .fill(waiting ? Color(red: 0.96, green: 0.77, blue: 0.26)
                      : status == .idle ? Color.white.opacity(0.35) : Color(red: 0.36, green: 0.82, blue: 0.5))
                .frame(width: 6, height: 6)
                .opacity(moving && pulse ? 0.35 : 1)
                .animation(moving ? .easeInOut(duration: 0.8).repeatForever() : .default, value: pulse)
            Text(status.label)
                .font(.system(size: 11))
                .foregroundStyle(waiting ? Color(red: 0.96, green: 0.77, blue: 0.26) : .white.opacity(0.6))
            TimelineView(.periodic(from: .now, by: 20)) { context in
                Text(agent.elapsed(now: context.date))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .onAppear { pulse = true }
    }
}

/// The tools, one row each, then Quit.
private struct ToolRows: View {
    let dopamine: DopamineModel
    let stick: StickModel

    var body: some View {
        VStack(spacing: 0) {
            ToolRow(title: "Dopamine", symbol: "bolt.fill", on: dopamine.on == true, detail: dopamine.error) {
                if let current = dopamine.on, !dopamine.busy { dopamine.set(!current) }
            }
            ToolRow(title: "Stick", symbol: "hand.point.up.left.fill", on: stick.on,
                    detail: stick.on ? nil : "Paused, agents cannot click or type") {
                stick.set(!stick.on)
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

/// Bean in the look its seed gives, or plain without a seed. A dressed Bean
/// sits in a fixed box with room for hats, props and shoes, so the rows
/// line up.
private struct BeanView: View {
    let pixel: CGFloat
    /// The part of Bean's grid drawn: left, top, width and height in cells.
    private let cells: (x: Int, y: Int, width: Int, height: Int)
    private let dressed: (x: Int, y: Int, grid: Wardrobe.Grid)

    init(seed: String?, pixel: CGFloat) {
        self.pixel = pixel
        if let seed {
            let look = Wardrobe.look(seed: seed)
            dressed = Wardrobe.dress(look.items, color: look.color)
            cells = (-3, -7, 24, 19)
        } else {
            dressed = Wardrobe.dress([])
            cells = (0, 0, 18, 10)
        }
    }

    var body: some View {
        let (cells, dressed, pixel) = (cells, dressed, pixel)
        Canvas { context, _ in
            for (row, line) in dressed.grid.enumerated() {
                for (column, color) in line.enumerated() {
                    guard let color else { continue }
                    let x = column - dressed.x - cells.x, y = row - dressed.y - cells.y
                    guard (0..<cells.width).contains(x), (0..<cells.height).contains(y) else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel,
                                             width: pixel, height: pixel)),
                                 with: .color(Color(red: Double(color >> 16 & 0xFF) / 255,
                                                    green: Double(color >> 8 & 0xFF) / 255,
                                                    blue: Double(color & 0xFF) / 255)))
                }
            }
        }
        .frame(width: CGFloat(cells.width) * pixel, height: CGFloat(cells.height) * pixel)
    }
}
