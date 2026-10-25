import XCTest
@testable import KeyboardCore

final class ResolverTests: XCTestCase {
    private let available: Set<String> = ["abc", "pinyin"]

    func testExplicitRuleWinsOverMemoryAndDefault() {
        var config = Config()
        config.apps = ["com.example.editor": "pinyin"]
        config.defaultInputSource = "abc"
        let memory = Memory(apps: ["com.example.editor": "abc"])

        XCTAssertEqual(
            Resolver.target(bundleID: "com.example.editor", config: config,
                            memory: memory, available: available),
            "pinyin"
        )
    }

    func testMemoryWinsOverDefault() {
        var config = Config()
        config.defaultInputSource = "abc"
        let memory = Memory(apps: ["com.example.browser": "pinyin"])

        XCTAssertEqual(
            Resolver.target(bundleID: "com.example.browser", config: config,
                            memory: memory, available: available),
            "pinyin"
        )
    }

    func testMemoryIsIgnoredWhenRememberingIsOff() {
        var config = Config()
        config.rememberLastInputSource = false
        config.defaultInputSource = "abc"
        let memory = Memory(apps: ["com.example.browser": "pinyin"])

        XCTAssertEqual(
            Resolver.target(bundleID: "com.example.browser", config: config,
                            memory: memory, available: available),
            "abc"
        )
    }

    func testUnavailableSourceFallsThrough() {
        var config = Config()
        config.apps = ["com.example.editor": "removed-method"]
        config.defaultInputSource = "abc"
        let memory = Memory(apps: ["com.example.editor": "pinyin"])

        XCTAssertEqual(
            Resolver.target(bundleID: "com.example.editor", config: config,
                            memory: memory, available: available),
            "pinyin"
        )
    }

    func testNoUsableCandidateReturnsNil() {
        var config = Config()
        config.defaultInputSource = "removed-method"
        XCTAssertNil(
            Resolver.target(bundleID: "com.example.app", config: config,
                            memory: Memory(), available: available)
        )
    }

    func testCandidatesAreTrimmed() {
        var config = Config()
        config.apps = ["com.example.editor": " pinyin "]

        XCTAssertEqual(
            Resolver.target(bundleID: "com.example.editor", config: config,
                            memory: Memory(), available: available),
            "pinyin"
        )
    }

    func testExcludedAndOwnAppsAreSkipped() {
        var config = Config()
        config.excludedApps = ["com.apple.loginwindow"]
        XCTAssertFalse(Resolver.shouldApply(bundleID: "com.apple.loginwindow", config: config,
                                           ownBundleID: "local.mkbd.MKbd"))
        XCTAssertFalse(Resolver.shouldApply(bundleID: "local.mkbd.MKbd", config: config,
                                           ownBundleID: "local.mkbd.MKbd"))
        XCTAssertTrue(Resolver.shouldApply(bundleID: "com.example.editor", config: config,
                                           ownBundleID: "local.mkbd.MKbd"))
    }

    func testDisabledSwitchesNothing() {
        var config = Config()
        config.enabled = false
        XCTAssertFalse(Resolver.shouldApply(bundleID: "com.example.editor", config: config,
                                           ownBundleID: "local.mkbd.MKbd"))
    }
}
