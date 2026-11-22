import Foundation
import Testing
@testable import ZyxKit

@Test func noticeReadsTheHookURL() throws {
    var parts = URLComponents(string: "zyx://done")!
    parts.queryItems = [
        URLQueryItem(name: "pane", value: "%16"),
        URLQueryItem(name: "title", value: "zyx menubar 動態島框架"),
        URLQueryItem(name: "message", value: "Clawd 拼出來了。\n\n細節"),
        URLQueryItem(name: "active", value: "0"),
    ]
    let notice = try #require(Notice(url: parts.url!))
    #expect(notice.title == "zyx menubar 動態島框架")
    #expect(notice.message == "Clawd 拼出來了。")
    #expect(!notice.active)
    #expect(notice.jump == [["select-window", "-t", "%16"], ["select-pane", "-t", "%16"]])
}

@Test func noticeRejectsOtherURLsAndPanes() {
    #expect(Notice(url: URL(string: "zyx://other?pane=%251")!) == nil)
    // A pane is "%" and digits only: it goes to tmux as an argument.
    #expect(Notice(url: URL(string: "zyx://done?pane=%25;rm")!) == nil)
    #expect(Notice(url: URL(string: "zyx://done?pane=%25")!) == nil)
    #expect(Notice(url: URL(string: "zyx://done?pane=%253")!)?.title == "Claude Code")
}

@Test func noticeHidesWhenItsWindowIsInFront() {
    let notice = Notice(url: URL(string: "zyx://done?pane=%253&active=1")!)!
    #expect(!notice.worthShowing(terminalInFront: true))
    #expect(notice.worthShowing(terminalInFront: false))
}
