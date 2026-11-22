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
