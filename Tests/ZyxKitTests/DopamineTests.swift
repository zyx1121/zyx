import Testing
@testable import ZyxKit

@Test func parsesSleepDisabled() {
    let on = "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n sleep 1\n"
    let off = "System-wide power settings:\n SleepDisabled\t\t0\n"
    #expect(Dopamine.parse(on) == true)
    #expect(Dopamine.parse(off) == false)
    #expect(Dopamine.parse("Currently in use:\n sleep 1\n") == nil)
}

@Test func ruleAllowsOnlyPmset() throws {
    let rule = try #require(Dopamine.sudoersRule(user: "loki"))
    #expect(rule.contains("loki ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"))
}

@Test func ruleRejectsOddUserNames() {
    for name in ["", "Root ALL", "a,b", "x\nALL ALL=(ALL) ALL", "%admin", "a b"] {
        #expect(Dopamine.sudoersRule(user: name) == nil)
    }
}
