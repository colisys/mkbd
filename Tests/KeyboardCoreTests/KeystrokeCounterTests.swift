import XCTest
@testable import KeyboardCore

final class KeystrokeCounterTests: XCTestCase {
    func testCountsInsideWindow() {
        var counter = KeystrokeCounter(window: 60)
        counter.record(at: 100)
        counter.record(at: 120)
        counter.record(at: 159)
        XCTAssertEqual(counter.count(now: 160), 3)
    }

    func testOldKeystrokesExpire() {
        var counter = KeystrokeCounter(window: 60)
        counter.record(at: 100)
        counter.record(at: 150)
        XCTAssertEqual(counter.count(now: 161), 1)
        XCTAssertEqual(counter.count(now: 210), 1)
        XCTAssertEqual(counter.count(now: 211), 0)
    }

    func testPruneKeepsRecentEntries() {
        var counter = KeystrokeCounter(window: 60)
        counter.record(at: 100)
        counter.record(at: 140)
        counter.prune(now: 170)
        XCTAssertEqual(counter.count(now: 170), 1)
        XCTAssertEqual(counter.count(now: 201), 0)
    }

    func testRecordsAtHighRate() {
        var counter = KeystrokeCounter(window: 60)
        for index in 0..<500 {
            counter.record(at: Double(index) * 0.1)
        }
        XCTAssertEqual(counter.count(now: 50), 500)
        // At 60.05 s the keystroke recorded at 0 has just left the window.
        XCTAssertEqual(counter.count(now: 60.05), 499)
    }

    func testEmptyCounterIsZero() {
        let counter = KeystrokeCounter(window: 60)
        XCTAssertEqual(counter.count(now: 0), 0)
    }
}
