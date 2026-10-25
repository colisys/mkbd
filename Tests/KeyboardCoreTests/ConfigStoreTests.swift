import XCTest
@testable import KeyboardCore

final class ConfigStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ConfigStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkbd-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ConfigStore(url: directory.appendingPathComponent("config.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadOrCreateWritesEditableDefaults() throws {
        let config = try store.loadOrCreate(defaultInputSource: "com.apple.keylayout.ABC")

        XCTAssertEqual(config.version, Config.currentVersion)
        XCTAssertTrue(config.enabled)
        XCTAssertTrue(config.rememberLastInputSource)
        XCTAssertEqual(config.defaultInputSource, "com.apple.keylayout.ABC")
        XCTAssertEqual(config.apps, [:])
        XCTAssertEqual(config.excludedApps, Config.systemExcludedApps)
        XCTAssertEqual(try store.load(), config)

        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testRoundTripKeepsRulesAndFlags() throws {
        var config = Config(defaultInputSource: "com.apple.keylayout.ABC")
        config.apps = ["com.apple.Terminal": "com.apple.inputmethod.SCIM.Shuangpin"]
        config.rememberLastInputSource = false
        config.excludedApps.append("com.example.game")
        try store.save(config)

        XCTAssertEqual(try store.load(), config)
    }

    func testPartialConfigGetsDefaults() throws {
        let partial = Data(#"{"apps":{"com.apple.Terminal":"com.apple.keylayout.ABC"}}"#.utf8)
        try partial.write(to: store.url)

        let config = try XCTUnwrap(store.load())
        XCTAssertTrue(config.enabled)
        XCTAssertTrue(config.rememberLastInputSource)
        XCTAssertNil(config.defaultInputSource)
        XCTAssertEqual(config.apps["com.apple.Terminal"], "com.apple.keylayout.ABC")
        XCTAssertEqual(config.excludedApps, Config.systemExcludedApps)
    }

    func testCorruptConfigThrowsAndIsNotReplaced() throws {
        let broken = Data("{ this is not json".utf8)
        try broken.write(to: store.url)

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.loadOrCreate(defaultInputSource: nil))
        XCTAssertEqual(try Data(contentsOf: store.url), broken)
    }

    func testMissingFileLoadsAsNil() throws {
        XCTAssertNil(try store.load())
    }

    func testDefaultPathsMatchFamilyLayout() {
        XCTAssertTrue(ConfigStore.defaultURL.path.hasSuffix("/Library/Application Support/MKbd/config.json"))
        XCTAssertTrue(MemoryStore.defaultURL.path.hasSuffix("/Library/Application Support/MKbd/memory.json"))
    }
}

final class MemoryStoreTests: XCTestCase {
    private var directory: URL!
    private var store: MemoryStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkbd-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = MemoryStore(url: directory.appendingPathComponent("memory.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingMemoryStartsEmpty() throws {
        XCTAssertEqual(try store.load(), Memory())
    }

    func testRoundTrip() throws {
        let memory = Memory(apps: [
            "com.apple.Terminal": "com.apple.keylayout.ABC",
            "com.example.browser": "com.apple.inputmethod.SCIM.ITABC",
        ])
        try store.save(memory)
        XCTAssertEqual(try store.load(), memory)

        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptMemoryThrows() throws {
        try Data("not json".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }
}
