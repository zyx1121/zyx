import Foundation
import Testing
@testable import ZyxKit

private let session = #"{"pid":12729,"sessionId":"e969af17","cwd":"/Users/loki","startedAt":1795357153221,"tmux":"0:@22.%22","name":"loki-25","status":"busy"}"#

@Test func readsASessionFile() {
    let agent = Agent(json: Data(session.utf8))
    #expect(agent?.id == "e969af17")
    #expect(agent?.pane == "%22")
    #expect(agent?.status == .working)
    #expect(agent?.status.label == "Working")
    #expect(Agent(json: Data("{}".utf8)) == nil)
}

@Test func loadsOnlyRunningSessionsOldestFirst() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = [
        (1, #"{"pid":1,"sessionId":"new","startedAt":20,"status":"idle"}"#),
        (2, #"{"pid":2,"sessionId":"old","startedAt":10,"status":"waiting_for_input"}"#),
        (3, #"{"pid":3,"sessionId":"gone","startedAt":5}"#),
    ]
    for (pid, json) in files {
        try Data(json.utf8).write(to: directory.appendingPathComponent("\(pid).json"))
    }
    try Data("x".utf8).write(to: directory.appendingPathComponent("1.abc.key"))
    let agents = Agent.load(from: directory) { $0 != 3 }
    #expect(agents.map(\.id) == ["old", "new"])
    #expect(agents[0].status.label == "Waiting for input")
    #expect(agents[0].pane == nil)
}

@Test func waitingSessionsComeFirstWithTheirReason() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = [
        (1, #"{"pid":1,"sessionId":"old","startedAt":10,"status":"busy"}"#),
        (2, #"{"pid":2,"sessionId":"asks","startedAt":20,"status":"waiting","waitingFor":"input needed"}"#),
    ]
    for (pid, json) in files {
        try Data(json.utf8).write(to: directory.appendingPathComponent("\(pid).json"))
    }
    let agents = Agent.load(from: directory) { _ in true }
    #expect(agents.map(\.id) == ["asks", "old"])
    #expect(agents[0].status.label == "Input needed")
    #expect(agents[0].status.isWaiting)
}

@Test func elapsedIsShort() {
    let json = #"{"pid":1,"sessionId":"a","startedAt":0,"statusUpdatedAt":1000000}"#
    let agent = Agent(json: Data(json.utf8))!
    let at = { (seconds: Double) in Date(timeIntervalSince1970: 1000 + seconds) }
    #expect(agent.elapsed(now: at(30)) == "<1m")
    #expect(agent.elapsed(now: at(12 * 60)) == "12m")
    #expect(agent.elapsed(now: at(2 * 3600)) == "2h")
    #expect(agent.elapsed(now: at(2 * 3600 + 5 * 60)) == "2h 5m")
}

@Test func onlyCommandsThatActAreShown() {
    #expect(Agent.action("click") == "Clicking")
    #expect(Agent.action("paste") == "Typing")
    #expect(Agent.action("status") == nil)
}

@Test func findsTheProcessOnALoopbackPort() throws {
    let server = socket(AF_INET, SOCK_STREAM, 0)
    let client = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(server); close(client) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    try withUnsafeMutablePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
            #expect(bind(server, raw, length) == 0)
            #expect(listen(server, 1) == 0)
            #expect(getsockname(server, raw, &length) == 0)
            #expect(connect(client, raw, length) == 0)
            #expect(getsockname(client, raw, &length) == 0)
            _ = try #require(Optional(raw))
        }
    }
    let port = UInt16(bigEndian: address.sin_port)
    #expect(Peer.session(fromPort: port, sessions: [99999, getpid()]) == getpid())
    #expect(Peer.session(fromPort: port, sessions: [99999]) == nil)
}
