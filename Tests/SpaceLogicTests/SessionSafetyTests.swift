import XCTest
@testable import SpaceLogic

final class SessionSafetyTests: XCTestCase {
    func state(locked: Bool = false, console: Bool = true, login: Bool = true, asleep: Bool = false, front: String? = "com.apple.finder") -> SessionState {
        SessionState(screenLocked: locked, onConsole: console, loginDone: login, displayAsleep: asleep, frontmostBundleID: front)
    }

    func testNormalSessionIsSafe() { XCTAssertTrue(state().isSafe); XCTAssertEqual(state().blockers, []) }
    func testLockedIsNotSafe() { XCTAssertEqual(state(locked: true).blockers, ["screen locked"]) }
    func testNotOnConsoleIsNotSafe() { XCTAssertFalse(state(console: false).isSafe) }
    func testLoginNotDoneIsNotSafe() { XCTAssertFalse(state(login: false).isSafe) }
    func testDisplayAsleepIsNotSafe() { XCTAssertFalse(state(asleep: true).isSafe) }
    func testLoginWindowFrontmostIsNotSafe() { XCTAssertFalse(state(front: "com.apple.loginwindow").isSafe) }
    func testUnknownFrontmostIsAllowed() { XCTAssertTrue(state(front: nil).isSafe) }

    func testWakeWithoutUnlockStaysUnsafe() {
        // Observed: after screens wake the display is awake but the session is still locked.
        XCTAssertFalse(state(locked: true, asleep: false, front: "com.apple.loginwindow").isSafe)
    }

    func testMultipleBlockersListed() {
        XCTAssertEqual(state(locked: true, asleep: true).blockers, ["screen locked", "display asleep"])
    }

    func testLatchBlocksStartWhenUnsafe() {
        var l = InterruptionLatch()
        XCTAssertFalse(l.begin(state: state(locked: true)))
    }

    func testLatchAllowsRunWhenSafe() {
        var l = InterruptionLatch()
        XCTAssertTrue(l.begin(state: state()))
        XCTAssertTrue(l.shouldContinue(state: state()))
    }

    func testInterruptionStopsRunEvenIfPolledStateStillLooksSafe() {
        var l = InterruptionLatch()
        _ = l.begin(state: state())
        l.interrupt()                                   // lock notification arrived first
        XCTAssertFalse(l.shouldContinue(state: state()))
    }

    func testStateTurningUnsafeStopsRun() {
        var l = InterruptionLatch()
        _ = l.begin(state: state())
        XCTAssertFalse(l.shouldContinue(state: state(locked: true)))
    }

    func testNewRunClearsEarlierInterruptionOnlyWhenSafe() {
        var l = InterruptionLatch()
        l.interrupt()
        XCTAssertFalse(l.shouldContinue(state: state()))
        XCTAssertFalse(l.begin(state: state(locked: true)))
        XCTAssertTrue(l.interrupted)
        XCTAssertTrue(l.begin(state: state()))
        XCTAssertFalse(l.interrupted)
    }
}
