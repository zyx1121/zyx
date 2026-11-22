// stickd: the macOS desktop daemon of zyx1121/stick, hosted in zyx.
//
// Copied from stick's macos/stickd.swift (commit 1e5bfec). zyx runs it in its
// own process instead of a LaunchAgent: zyx is signed with a Developer ID and
// notarized, so the Screen Recording and Accessibility grants survive a
// rebuild, where the ad-hoc signed Stick.app lost them. Changes from stick:
// `startStickd` replaces `main`, a missing token is created, a busy port
// returns an error instead of crashing, and zyx can read and set the pause.
//
// It runs as a LaunchAgent in the user's login session, so it can hold the
// Screen Recording and Accessibility permissions that an ssh session never
// gets. It speaks the same small protocol as the Windows daemon (fwd.cs):
//   POST /run   body = script, one command per line; X-Fw-Force: 1 skips the idle guard
//   GET  /file?name=<name>   a screenshot from the out folder
// Every request carries X-Fw-Token. It listens on 127.0.0.1 only.

import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import Security
import ImageIO
import UniformTypeIdentifiers

let version = "1.0.0"
let port: UInt16 = 9877
let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/stick")
let outDir = root.appendingPathComponent("out")

struct Fail: Error { let message: String; init(_ m: String) { message = m } }

// ------------------------------------------------------------------ state

let inputLock = NSLock()
let stateLock = NSLock()
let logLock = NSLock()
var token = ""
var paused = false
var ourLastInput: TimeInterval = 0
var refs: [String: Ref] = [:]
var fileSeq = 0
// Transform of the last shot: image pixel = (screen point - origin) * scale.
var shotX = 0.0, shotY = 0.0, shotScale = 1.0
var logLines: [String] = []

struct Ref { let el: AXUIElement; let rect: CGRect }

let inputCmds: Set<String> = ["click", "move", "scroll", "key", "type", "paste", "focus"]

func locked<T>(_ l: NSLock, _ f: () throws -> T) rethrows -> T { l.lock(); defer { l.unlock() }; return try f() }

var onCommand: (@Sendable (String, Int32?) -> Void)?
var identify: (@Sendable (UInt16) -> Int32?)?

/// Calls `handler` on the main thread after each command, with its first
/// word and the client `stickdIdentify` named, if any.
public func stickdObserve(_ handler: @escaping @Sendable (String, Int32?) -> Void) {
  locked(stateLock) { onCommand = handler }
}

/// Names the client of each request from its TCP port, while the connection
/// is still open: zyx returns the pid of the Claude Code session behind it.
public func stickdIdentify(_ resolver: @escaping @Sendable (UInt16) -> Int32?) {
  locked(stateLock) { identify = resolver }
}

/// The client's TCP port on connection `c`.
func peerPort(_ c: Int32) -> UInt16? {
  var address = sockaddr_in()
  var length = socklen_t(MemoryLayout<sockaddr_in>.size)
  let got = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(c, $0, &length) }
  }
  return got == 0 ? UInt16(bigEndian: address.sin_port) : nil
}

func log(_ line: String, _ ok: Bool, _ ms: Int, _ result: String) {
  if let notify = locked(stateLock, { onCommand }) {
    let word = String(line.split(separator: " ").first ?? "")
    let client = Thread.current.threadDictionary["stickdClient"] as? Int32
    DispatchQueue.main.async { notify(word, client) }
  }
  let first = result.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
  let stamp = ISO8601DateFormatter().string(from: Date())
  locked(logLock) {
    logLines.append("\(stamp) \(ok ? "ok " : "ERR") \(ms)ms \(line) -> \(first.prefix(160))")
    if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
  }
}

// ------------------------------------------------------------------- http

func serve() {
  let fd = socket(AF_INET, SOCK_STREAM, 0)
  guard fd >= 0 else { log("start", false, 0, "socket failed"); return }
  var yes: Int32 = 1
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = inet_addr("127.0.0.1")
  let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
  guard bound == 0, listen(fd, 16) == 0 else {
    log("start", false, 0, "cannot listen on 127.0.0.1:\(port): errno \(errno)")
    close(fd)
    return
  }
  while true {
    let c = accept(fd, nil, nil)
    if c < 0 { continue }
    Thread.detachNewThread { handle(c) }
  }
}

func readRequest(_ c: Int32) -> (method: String, path: String, headers: [String: String], body: Data)? {
  var data = Data()
  var buf = [UInt8](repeating: 0, count: 65536)
  var headerEnd: Range<Data.Index>?
  while headerEnd == nil {
    let n = read(c, &buf, buf.count)
    if n <= 0 { return nil }
    data.append(buf, count: n)
    headerEnd = data.range(of: Data("\r\n\r\n".utf8))
    if data.count > 64 * 1024 && headerEnd == nil { return nil }
  }
  let head = String(decoding: data[..<headerEnd!.lowerBound], as: UTF8.self)
  var lines = head.components(separatedBy: "\r\n")
  let start = lines.removeFirst().split(separator: " ")
  guard start.count >= 2 else { return nil }
  var headers: [String: String] = [:]
  for line in lines {
    guard let i = line.firstIndex(of: ":") else { continue }
    headers[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
  }
  let length = Int(headers["content-length"] ?? "0") ?? 0
  if length > 1 << 20 { return nil }
  var body = data[headerEnd!.upperBound...]
  while body.count < length {
    let n = read(c, &buf, buf.count)
    if n <= 0 { return nil }
    body.append(contentsOf: buf[0..<n])
  }
  return (String(start[0]), String(start[1]), headers, Data(body))
}

func respond(_ c: Int32, _ code: Int, _ body: Data, _ type: String) {
  let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 500: "Error"][code] ?? "Error"
  var out = Data("HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
  out.append(body)
  out.withUnsafeBytes { p in
    var sent = 0
    while sent < out.count {
      let n = write(c, p.baseAddress! + sent, out.count - sent)
      if n <= 0 { break }
      sent += n
    }
  }
}

func reply(_ c: Int32, _ code: Int, _ text: String) {
  respond(c, code, Data((text.hasSuffix("\n") ? text : text + "\n").utf8), "text/plain; charset=utf-8")
}

/// Compare in constant time, so the token cannot be guessed one byte at a time.
func same(_ a: String, _ b: String) -> Bool {
  let x = Array(a.utf8), y = Array(b.utf8)
  if x.count != y.count { return false }
  var d: UInt8 = 0
  for i in 0..<x.count { d |= x[i] ^ y[i] }
  return d == 0
}

func handle(_ c: Int32) {
  defer { close(c) }
  guard let req = readRequest(c) else { return }
  guard same(req.headers["x-fw-token"] ?? "", token) else { return reply(c, 401, "bad token") }
  let comps = URLComponents(string: "http://x" + req.path)
  let path = comps?.path ?? ""
  if path == "/file" && req.method == "GET" {
    let name = (comps?.queryItems?.first { $0.name == "name" }?.value ?? "") as NSString
    let base = name.lastPathComponent
    let file = outDir.appendingPathComponent(base)
    guard !base.isEmpty, base != ".", base != "..", let data = try? Data(contentsOf: file) else { return reply(c, 404, "no such file: \(base)") }
    return respond(c, 200, data, "application/octet-stream")
  }
  if path == "/run" && req.method == "POST" {
    if let port = peerPort(c), let resolver = locked(stateLock, { identify }) {
      Thread.current.threadDictionary["stickdClient"] = resolver(port)
    }
    let (ok, text) = runScript(String(decoding: req.body, as: UTF8.self), force: req.headers["x-fw-force"] == "1")
    return reply(c, ok ? 200 : 400, text)
  }
  reply(c, 404, "unknown path")
}

// ----------------------------------------------------------------- script

func name(_ line: String) -> String { String(line.split(separator: " ", maxSplits: 1).first ?? "").lowercased() }
func rest(_ line: String) -> String {
  guard let i = line.firstIndex(of: " ") else { return "" }
  return line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
}

/// Typed and pasted text never reaches the log: it may be a secret.
func redact(_ line: String) -> String {
  let n = name(line)
  return n == "type" || n == "paste" ? "\(n) <\(rest(line).count) chars>" : line
}

func tokens(_ s: String) -> [String] {
  var out: [String] = [], cur = "", quoted = false, any = false
  let chars = Array(s)
  var i = 0
  while i < chars.count {
    let ch = chars[i]
    if ch == "\\" && quoted && i + 1 < chars.count && chars[i + 1] == "\"" { cur.append("\""); i += 1 }
    else if ch == "\"" { quoted.toggle(); any = true }
    else if !quoted && ch.isWhitespace { if !cur.isEmpty || any { out.append(cur); cur = ""; any = false } }
    else { cur.append(ch) }
    i += 1
  }
  if !cur.isEmpty || any { out.append(cur) }
  return out
}

func flag(_ a: inout [String], _ f: String) -> Bool {
  guard let i = a.firstIndex(of: f) else { return false }
  a.remove(at: i)
  return true
}

func opt(_ a: inout [String], _ f: String, _ def: String) throws -> String {
  guard let i = a.firstIndex(of: f) else { return def }
  guard i + 1 < a.count else { throw Fail("\(f) needs a value") }
  let v = a[i + 1]
  a.removeSubrange(i...(i + 1))
  return v
}

func int(_ s: String, _ what: String) throws -> Int {
  guard let v = Int(s) else { throw Fail("\(what) must be a number, got: \(s)") }
  return v
}

func need(_ s: String, _ usage: String) throws -> String {
  if s.isEmpty { throw Fail("usage: \(usage)") }
  return s
}

func runScript(_ body: String, force: Bool) -> (Bool, String) {
  let lines = body.replacingOccurrences(of: "\r", with: "").split(separator: "\n")
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
  if lines.isEmpty { return (false, "empty script; try: help") }
  let input = lines.contains { inputCmds.contains(name($0)) }
  if input { inputLock.lock() }
  defer { if input { inputLock.unlock() } }
  var out = ""
  let many = lines.count > 1
  for (i, line) in lines.enumerated() {
    let t0 = Date()
    let shown = redact(line)
    do {
      var res = try exec(line, force: force)
      if res.isEmpty { res = "ok" }
      log(shown, true, Int(Date().timeIntervalSince(t0) * 1000), res)
      out += (many ? "[\(i + 1)] \(shown) -> \(res)" : res) + "\n"
    } catch {
      let msg = (error as? Fail)?.message ?? "\(error)"
      log(shown, false, Int(Date().timeIntervalSince(t0) * 1000), msg)
      out += "ERR" + (many ? " line \(i + 1) (\(shown))" : "") + ": \(msg)\n"
      if many && i + 1 < lines.count { out += "stopped; \(lines.count - i - 1) line(s) not run\n" }
      return (false, out)
    }
  }
  return (true, out)
}

func exec(_ line: String, force: Bool) throws -> String {
  let n = name(line), r = rest(line)
  var a = tokens(r)
  if inputCmds.contains(n) { try guardInput(force) }
  switch n {
  case "help": return help
  case "status": return status()
  case "windows": return windowsList()
  case "focus": return try focus(try need(r, "focus <window>"))
  case "waitfor": return try waitFor(a)
  case "wait": Thread.sleep(forTimeInterval: Double(min(try int(try need(r, "wait <ms>"), "ms"), 60000)) / 1000); return ""
  case "snap": return try snap(&a)
  case "invoke": return try invoke(try need(r, "invoke <ref>"))
  case "set": return try setValue(r)
  case "click": return try click(&a)
  case "move": let p = try target(try need(r, "move <target>")); moveTo(p); return "moved \(Int(p.x)),\(Int(p.y))"
  case "scroll": return try scroll(a)
  case "key":
    if a.isEmpty { throw Fail("usage: key <combo>...") }
    for combo in a { try keyCombo(combo) }
    return ""
  case "type": try typeText(r); return "typed \(r.count) chars"
  case "paste": try paste(r); return "pasted \(r.count) chars"
  case "shot": return try shot(&a)
  case "exec": return try run(r)
  case "log": return tail(a.first.map { (try? int($0, "count")) ?? 20 } ?? 20)
  case "drag", "keydown", "keyup", "rec": throw Fail("\(n) is not available on macOS yet")
  default: throw Fail("unknown command: \(n); try: help")
  }
}

let help = """
stickd commands (one per line; a script stops at the first error)
look
  status                          version, screen, cursor, idle time, permissions, front window
  windows                         visible windows: app, title, rect (points)
  snap [window] [--max N]         accessibility tree as text; each element gets a ref (e1, e2..)
  shot [screen|window [name]|region x,y,w,h|<ref>] [--max 1280] [--q 70]
                                  JPEG, scaled so the long side is at most --max pixels
  log [N]                         last N commands
act without the cursor
  invoke <ref>                    press an element through accessibility
  set <ref> <text>                set the value of a text field
  exec <command line>             start a command in the login session (open -a Safari)
  exec --wait [seconds] <command> run a command, wait, return its output
act with the cursor and keyboard (refused while a person uses the machine)
  focus <window>                  bring a window to the front (title substring or app name)
  click <target> [--right] [--double]
  move <target>
  scroll <target> <lines>         positive scrolls up
  key <combo>..                   enter, cmd+s, cmd+shift+4, esc, f5 ..
  type <text>                     Unicode key events
  paste <text>                    through the clipboard; use when type is mangled
flow
  wait <ms>
  waitfor <window> [seconds]      wait until a window exists
targets
  e12        a ref from the last snap (its center)
  @640,360   a pixel in the last shot
  640,360    a screen point
Ctrl+Option+F12 on the machine pauses and resumes all cursor and keyboard commands.
"""

// ------------------------------------------------------------------ guard

func idleSeconds() -> TimeInterval {
  CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

func guardInput(_ force: Bool) throws {
  if locked(stateLock, { paused }) { throw Fail("paused by Ctrl+Option+F12 on the machine; press it again to resume") }
  if !AXIsProcessTrusted() { throw Fail("stickd has no Accessibility permission; grant it in System Settings > Privacy & Security > Accessibility") }
  if force { return }
  let now = Date().timeIntervalSince1970
  let idle = idleSeconds()
  let lastInput = now - idle
  let notOurs = lastInput - locked(stateLock, { ourLastInput }) > 0.15
  if notOurs && idle < 3 {
    throw Fail("a person is using the machine (last input \(Int(idle * 1000)) ms ago); retry later or pass force")
  }
}

func post(_ e: CGEvent?) {
  e?.post(tap: .cghidEventTap)
  locked(stateLock) { ourLastInput = Date().timeIntervalSince1970 }
}

// ----------------------------------------------------------------- screen

func status() -> String {
  let screen = NSScreen.screens.first?.frame ?? .zero
  let cursor = CGEvent(source: nil)?.location ?? .zero
  let front = NSWorkspace.shared.frontmostApplication
  let win = visibleWindows().first { $0.pid == front?.processIdentifier }
  return """
  stickd \(version)
  screen \(Int(screen.width))x\(Int(screen.height)) points, \(NSScreen.screens.count) display(s)
  cursor \(Int(cursor.x)),\(Int(cursor.y))
  idle \(Int(idleSeconds()))s
  paused \(locked(stateLock, { paused }) ? "yes" : "no")
  screen recording \(CGPreflightScreenCaptureAccess() ? "yes" : "no (grant in System Settings > Privacy & Security > Screen & System Audio Recording)")
  accessibility \(AXIsProcessTrusted() ? "yes" : "no (grant in System Settings > Privacy & Security > Accessibility)")
  foreground \(front?.localizedName ?? "?") "\(win?.title ?? "")"
  """
}

struct Win { let id: CGWindowID; let pid: pid_t; let app: String; let title: String; let rect: CGRect }

func visibleWindows() -> [Win] {
  guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
  return list.compactMap { w in
    guard (w[kCGWindowLayer as String] as? Int) == 0,
          let id = w[kCGWindowNumber as String] as? CGWindowID,
          let pid = w[kCGWindowOwnerPID as String] as? pid_t,
          let b = w[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: b), rect.width > 1, rect.height > 1 else { return nil }
    return Win(id: id, pid: pid, app: w[kCGWindowOwnerName as String] as? String ?? "?", title: w[kCGWindowName as String] as? String ?? "", rect: rect)
  }
}

func describe(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }

func windowsList() -> String {
  let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
  var marked = false
  let lines = visibleWindows().map { w -> String in
    let star = !marked && w.pid == front
    if star { marked = true }
    return "\(star ? "* " : "  ")\(w.app) \"\(w.title)\" \(describe(w.rect))"
  }
  return lines.isEmpty ? "no windows" : lines.joined(separator: "\n")
}

func findWindow(_ q: String) -> Win? {
  let needle = q.lowercased()
  let all = visibleWindows()
  return all.first { $0.title.lowercased().contains(needle) } ?? all.first { $0.app.lowercased() == needle } ?? all.first { $0.app.lowercased().contains(needle) }
}

func frontWindow() -> Win? {
  let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
  return visibleWindows().first { $0.pid == front }
}

func axWindow(_ w: Win) -> AXUIElement? {
  let app = AXUIElementCreateApplication(w.pid)
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let list = value as? [AXUIElement] else { return nil }
  return list.first { (attr($0, kAXTitleAttribute) as? String ?? "") == w.title && w.title != "" }
    ?? list.first { frame($0).map { abs($0.minX - w.rect.minX) < 2 && abs($0.minY - w.rect.minY) < 2 } ?? false }
    ?? list.first
}

func focus(_ q: String) throws -> String {
  guard let w = findWindow(q) else { throw Fail("no window matches \"\(q)\"; run: windows") }
  NSRunningApplication(processIdentifier: w.pid)?.activate()
  if let el = axWindow(w) { AXUIElementPerformAction(el, kAXRaiseAction as CFString) }
  return "focused \(w.app) \"\(w.title)\""
}

func waitFor(_ a: [String]) throws -> String {
  guard !a.isEmpty else { throw Fail("usage: waitfor <window> [seconds]") }
  var q = a, secs = 10
  if q.count > 1, let s = Int(q.last!) { secs = s; q.removeLast() }
  let needle = q.joined(separator: " ")
  let end = Date().addingTimeInterval(Double(min(secs, 300)))
  while Date() < end {
    if let w = findWindow(needle) { return "found \(w.app) \"\(w.title)\"" }
    Thread.sleep(forTimeInterval: 0.25)
  }
  throw Fail("no window matching \"\(needle)\" after \(secs) s")
}

// ------------------------------------------------------------ accessibility

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func frame(_ el: AXUIElement) -> CGRect? {
  guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute),
        CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
  var point = CGPoint.zero, size = CGSize.zero
  AXValueGetValue(p as! AXValue, .cgPoint, &point)
  AXValueGetValue(s as! AXValue, .cgSize, &size)
  return CGRect(origin: point, size: size)
}

let interactive: Set<String> = ["Button", "CheckBox", "RadioButton", "TextField", "TextArea", "PopUpButton", "MenuButton", "ComboBox",
                                "Slider", "Link", "MenuItem", "MenuBarItem", "Tab", "Cell", "Row", "DisclosureTriangle", "SearchField", "Incrementor"]

func snap(_ a: inout [String]) throws -> String {
  guard AXIsProcessTrusted() else { throw Fail("stickd has no Accessibility permission; grant it in System Settings > Privacy & Security > Accessibility") }
  let max = try int(try opt(&a, "--max", "400"), "--max")
  let w: Win
  if a.isEmpty { guard let f = frontWindow() else { throw Fail("no foreground window") }; w = f }
  else { guard let f = findWindow(a.joined(separator: " ")) else { throw Fail("no window matches \"\(a.joined(separator: " "))\"; run: windows") }; w = f }
  guard let root = axWindow(w) else { throw Fail("\(w.app) exposes no accessibility window; use shot and @x,y targets") }
  var fresh: [String: Ref] = [:]
  var out = "window \(w.app) \"\(w.title)\" \(describe(w.rect))\n"
  var n = 0
  walk(root, 0, &fresh, &out, &n, max)
  locked(stateLock) { refs = fresh }
  if n == 0 { out += "no elements: this window draws its own interface; use shot and @x,y targets\n" }
  if n >= max { out += "stopped at \(max) elements; pass --max to see more\n" }
  return out.trimmingCharacters(in: .newlines)
}

func walk(_ el: AXUIElement, _ depth: Int, _ into: inout [String: Ref], _ out: inout String, _ n: inout Int, _ max: Int) {
  if n >= max || depth > 40 { return }
  let role = (attr(el, kAXRoleAttribute) as? String ?? "").replacingOccurrences(of: "AX", with: "")
  var label = attr(el, kAXTitleAttribute) as? String ?? ""
  if label.isEmpty { label = attr(el, kAXDescriptionAttribute) as? String ?? "" }
  if label.isEmpty, let v = attr(el, kAXValueAttribute) as? String { label = v }
  label = label.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
  if label.count > 80 { label = String(label.prefix(77)) + "..." }
  let rect = frame(el)
  let usable = rect.map { $0.width >= 1 && $0.height >= 1 } ?? false
  let show = depth > 0 && usable && (!label.isEmpty || interactive.contains(role))
  if show, let r = rect {
    n += 1
    let id = "e\(n)"
    into[id] = Ref(el: el, rect: r)
    out += String(repeating: "  ", count: min(depth, 12)) + "\(id) \(role)" + (label.isEmpty ? "" : " \"\(label)\"") + " \(describe(r))\n"
  }
  guard let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] else { return }
  for kid in kids where n < max {
    walk(kid, depth + (show || depth == 0 ? 1 : 0), &into, &out, &n, max)
  }
}

func getRef(_ id: String) throws -> Ref {
  guard let r = locked(stateLock, { refs[id] }) else { throw Fail("unknown ref \(id); run snap first") }
  return r
}

func invoke(_ id: String) throws -> String {
  let r = try getRef(id)
  for action in [kAXPressAction, kAXConfirmAction, kAXPickAction, kAXShowMenuAction] {
    if AXUIElementPerformAction(r.el, action as CFString) == .success { return "invoked \(id)" }
  }
  throw Fail("\(id) has no press action; try: click \(id)")
}

func setValue(_ r: String) throws -> String {
  guard let i = r.firstIndex(of: " ") else { throw Fail("usage: set <ref> <text>") }
  let id = String(r[..<i]), text = String(r[r.index(after: i)...])
  let ref = try getRef(id)
  let err = AXUIElementSetAttributeValue(ref.el, kAXValueAttribute as CFString, text as CFString)
  if err != .success { throw Fail("\(id) does not accept a value (error \(err.rawValue)); try: click \(id), then type") }
  return "set \(id) to \(text.count) chars"
}

// ----------------------------------------------------------- mouse and keys

func target(_ s: String) throws -> CGPoint {
  let t = s.trimmingCharacters(in: .whitespaces)
  if t.count > 1, t.first == "e", t.dropFirst().first?.isNumber == true {
    let r = try getRef(t)
    let f = frame(r.el) ?? r.rect
    return CGPoint(x: f.midX, y: f.midY)
  }
  let image = t.hasPrefix("@")
  let parts = (image ? String(t.dropFirst()) : t).split(separator: ",")
  guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
    throw Fail("bad target \"\(t)\"; use a ref (e12), an image pixel (@x,y) or a screen point (x,y)")
  }
  if image { return locked(stateLock) { CGPoint(x: shotX + x / shotScale, y: shotY + y / shotScale) } }
  return CGPoint(x: x, y: y)
}

func moveTo(_ p: CGPoint) {
  post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
  Thread.sleep(forTimeInterval: 0.04)
}

func click(_ a: inout [String]) throws -> String {
  let right = flag(&a, "--right"), twice = flag(&a, "--double")
  guard a.count == 1 else { throw Fail("usage: click <target> [--right] [--double]") }
  let p = try target(a[0])
  moveTo(p)
  let (down, up, button): (CGEventType, CGEventType, CGMouseButton) = right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
  for k in 1...(twice ? 2 : 1) {
    let d = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: p, mouseButton: button)
    let u = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: p, mouseButton: button)
    d?.setIntegerValueField(.mouseEventClickState, value: Int64(k))
    u?.setIntegerValueField(.mouseEventClickState, value: Int64(k))
    post(d)
    Thread.sleep(forTimeInterval: 0.03)
    post(u)
    Thread.sleep(forTimeInterval: 0.06)
  }
  return "clicked \(Int(p.x)),\(Int(p.y))"
}

func scroll(_ a: [String]) throws -> String {
  guard a.count == 2 else { throw Fail("usage: scroll <target> <lines>") }
  let p = try target(a[0])
  let lines = try int(a[1], "lines")
  moveTo(p)
  post(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(lines), wheel2: 0, wheel3: 0))
  return "scrolled \(lines)"
}

let keyCodes: [String: CGKeyCode] = {
  var m: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
    "n": 45, "m": 46, ".": 47, "`": 50,
    "enter": 36, "return": 36, "tab": 48, "space": 49, "backspace": 51, "esc": 53, "escape": 53, "delete": 117, "del": 117,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
  ]
  let f: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
  for (i, code) in f.enumerated() { m["f\(i + 1)"] = code }
  return m
}()

let modifiers: [String: CGEventFlags] = [
  "cmd": .maskCommand, "command": .maskCommand, "win": .maskCommand, "ctrl": .maskControl, "control": .maskControl,
  "alt": .maskAlternate, "opt": .maskAlternate, "option": .maskAlternate, "shift": .maskShift, "fn": .maskSecondaryFn,
]

func keyCombo(_ combo: String) throws {
  var flags: CGEventFlags = []
  var key: CGKeyCode?
  for part in combo.lowercased().split(separator: "+").map(String.init) {
    if let m = modifiers[part] { flags.insert(m) }
    else if let k = keyCodes[part] { key = k }
    else { throw Fail("unknown key \"\(part)\"; use names like enter, esc, tab, f5, cmd+s") }
  }
  guard let k = key else { throw Fail("\(combo) has no key, only modifiers") }
  let d = CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: true)
  let u = CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: false)
  d?.flags = flags
  u?.flags = flags
  post(d)
  Thread.sleep(forTimeInterval: 0.02)
  post(u)
  Thread.sleep(forTimeInterval: 0.04)
}

func typeText(_ text: String) throws {
  if text.isEmpty { throw Fail("usage: type <text>") }
  let units = Array(text.utf16)
  var i = 0
  while i < units.count {
    var chunk = Array(units[i..<min(i + 16, units.count)])
    // Never split a surrogate pair across two events.
    if chunk.count == 16, UTF16.isLeadSurrogate(chunk.last!) { chunk.removeLast() }
    for down in [true, false] {
      let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
      e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
      post(e)
    }
    i += chunk.count
    Thread.sleep(forTimeInterval: 0.02)
  }
}

func paste(_ text: String) throws {
  if text.isEmpty { throw Fail("usage: paste <text>") }
  let pb = NSPasteboard.general
  pb.clearContents()
  pb.setString(text, forType: .string)
  try keyCombo("cmd+v")
}

// ------------------------------------------------------------------- shot

func shot(_ a: inout [String]) throws -> String {
  guard CGPreflightScreenCaptureAccess() else {
    throw Fail("stickd has no Screen Recording permission; grant it in System Settings > Privacy & Security > Screen & System Audio Recording")
  }
  let max = try int(try opt(&a, "--max", "1280"), "--max")
  let q = try int(try opt(&a, "--q", "70"), "--q")
  let what = a.first?.lowercased() ?? "window"
  var args = ["-x", "-t", "png"]
  var rect: CGRect
  if what == "screen" {
    rect = CGDisplayBounds(CGMainDisplayID())
    args += ["-m"]
  } else if what == "window" {
    let w: Win
    if a.count > 1 { guard let f = findWindow(a.dropFirst().joined(separator: " ")) else { throw Fail("no window matches; run: windows") }; w = f }
    else { guard let f = frontWindow() else { throw Fail("no foreground window; use: shot screen") }; w = f }
    rect = w.rect
    args += ["-o", "-l", String(w.id)]
  } else if what == "region" {
    let p = a.count > 1 ? a[1].split(separator: ",").compactMap { Double($0) } : []
    guard p.count == 4 else { throw Fail("usage: shot region x,y,w,h") }
    rect = CGRect(x: p[0], y: p[1], width: p[2], height: p[3])
    args += ["-R", "\(Int(p[0])),\(Int(p[1])),\(Int(p[2])),\(Int(p[3]))"]
  } else if what.count > 1, what.first == "e", what.dropFirst().first?.isNumber == true {
    rect = try getRef(what).rect
    args += ["-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"]
  } else {
    throw Fail("usage: shot [screen|window [name]|region x,y,w,h|<ref>]")
  }
  if rect.width < 1 || rect.height < 1 { throw Fail("nothing to capture: the target is empty") }

  let raw = FileManager.default.temporaryDirectory.appendingPathComponent("stickd-\(UUID().uuidString).png")
  defer { try? FileManager.default.removeItem(at: raw) }
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = args + [raw.path]
  let err = Pipe()
  p.standardError = err
  try p.run()
  p.waitUntilExit()
  guard p.terminationStatus == 0, let src = CGImageSourceCreateWithURL(raw as CFURL, nil),
        let full = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    throw Fail("screencapture failed: " + String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
  }
  let pw = Double(full.width), ph = Double(full.height)
  let fit = min(1.0, Double(max) / Swift.max(pw, ph))
  let ow = Swift.max(1, Int((pw * fit).rounded())), oh = Swift.max(1, Int((ph * fit).rounded()))
  guard let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Fail("cannot scale the shot") }
  ctx.interpolationQuality = .high
  ctx.draw(full, in: CGRect(x: 0, y: 0, width: ow, height: oh))
  guard let small = ctx.makeImage() else { throw Fail("cannot scale the shot") }

  let seq = locked(stateLock) { () -> Int in fileSeq += 1; return fileSeq }
  let stamp = DateFormatter()
  stamp.dateFormat = "HHmmss"
  let name = "shot-\(seq)-\(stamp.string(from: Date())).jpg"
  let path = outDir.appendingPathComponent(name)
  guard let dest = CGImageDestinationCreateWithURL(path as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw Fail("cannot write \(name)") }
  CGImageDestinationAddImage(dest, small, [kCGImageDestinationLossyCompressionQuality: Double(Swift.max(10, Swift.min(95, q))) / 100] as CFDictionary)
  guard CGImageDestinationFinalize(dest) else { throw Fail("cannot write \(name)") }
  let bytes = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int) ?? 0
  // Image pixels per screen point, for @x,y targets.
  let scale = Double(ow) / rect.width
  locked(stateLock) { shotX = rect.minX; shotY = rect.minY; shotScale = scale }
  return "\(name) \(ow)x\(oh) of screen \(describe(rect)) scale \(String(format: "%.3f", scale)) \(bytes / 1024)KB; target its pixels as @x,y"
}

// ------------------------------------------------------------------- exec

func run(_ r: String) throws -> String {
  if r.isEmpty { throw Fail("usage: exec [--wait [seconds]] <command line>") }
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/sh")
  p.standardInput = FileHandle.nullDevice
  if !r.hasPrefix("--wait") {
    p.arguments = ["-c", r]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    return "started"
  }
  var cmd = String(r.dropFirst(6)).trimmingCharacters(in: .whitespaces)
  var secs = 120
  if let sp = cmd.firstIndex(of: " "), let s = Int(cmd[..<sp]) { secs = s; cmd = String(cmd[cmd.index(after: sp)...]).trimmingCharacters(in: .whitespaces) }
  if cmd.isEmpty { throw Fail("usage: exec --wait [seconds] <command line>") }
  p.arguments = ["-c", cmd + " 2>&1"]
  let out = Pipe()
  p.standardOutput = out
  var data = Data()
  let reader = Thread { data = out.fileHandleForReading.readDataToEndOfFile() }
  try p.run()
  reader.start()
  let end = Date().addingTimeInterval(Double(secs))
  while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }
  let done = !p.isRunning
  if !done { p.terminate() }
  p.waitUntilExit()
  Thread.sleep(forTimeInterval: 0.1)
  var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  if text.count > 6000 { text = "...(\(text.count - 6000) chars cut)\n" + String(text.suffix(6000)) }
  if !done { throw Fail("still running after \(secs) s, killed\n\(text)") }
  if p.terminationStatus != 0 { throw Fail("exit code \(p.terminationStatus)\n\(text)") }
  return text.isEmpty ? "exit code 0" : text
}

func tail(_ n: Int) -> String {
  let lines = locked(logLock) { logLines.suffix(Swift.max(1, Swift.min(n, 500))) }
  return lines.isEmpty ? "no commands yet" : lines.joined(separator: "\n")
}

// ------------------------------------------------------------------- main

let hotKeyHandler: EventHandlerUPP = { _, _, _ in
  let now = locked(stateLock) { () -> Bool in paused.toggle(); return paused }
  log("hotkey", true, 0, now ? "paused" : "resumed")
  return noErr
}

/// Whether input commands are refused, as Ctrl+Option+F12 toggles.
public func stickdIsPaused() -> Bool {
  locked(stateLock) { paused }
}

public func stickdSetPaused(_ value: Bool) {
  locked(stateLock) { paused = value }
  log("pause", true, 0, value ? "paused" : "resumed")
}

/// Starts the daemon inside the running app: the token, the hotkey and the
/// server on 127.0.0.1:9877. Call it once, on the main thread.
public func startStickd() {
  try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
  let tokenFile = root.appendingPathComponent("token")
  if let t = try? String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), t.count >= 16 {
    token = t
  } else {
    // The stick client reads this file over ssh, or locally, to talk to us.
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    token = bytes.map { String(format: "%02x", $0) }.joined()
    FileManager.default.createFile(atPath: tokenFile.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
  }
  let old = Date().addingTimeInterval(-86400)
  for f in (try? FileManager.default.contentsOfDirectory(at: outDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
    if let d = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d < old { try? FileManager.default.removeItem(at: f) }
  }
  // Ask once at start, so the prompts show up on the machine's screen.
  if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
  _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)

  var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
  InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
  var ref: EventHotKeyRef?
  RegisterEventHotKey(UInt32(kVK_F12), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x7374_6B64, id: 1), GetApplicationEventTarget(), 0, &ref)

  Thread.detachNewThread { serve() }
  log("start", true, 0, "stickd \(version) in zyx")
}
