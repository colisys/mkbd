import Foundation

/// User-editable configuration. JSON keys are intentionally readable so the
/// file can be maintained by hand; missing keys fall back to current defaults.
public struct Config: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var enabled: Bool
    public var rememberLastInputSource: Bool
    public var defaultInputSource: String?
    /// bundle ID → input source ID
    public var apps: [String: String]
    public var excludedApps: [String]

    public init(
        version: Int = Config.currentVersion,
        enabled: Bool = true,
        rememberLastInputSource: Bool = true,
        defaultInputSource: String? = nil,
        apps: [String: String] = [:],
        excludedApps: [String] = Config.systemExcludedApps
    ) {
        self.version = version
        self.enabled = enabled
        self.rememberLastInputSource = rememberLastInputSource
        self.defaultInputSource = defaultInputSource
        self.apps = apps
        self.excludedApps = excludedApps
    }

    /// System surfaces that appear as frontmost apps but must never trigger a
    /// switch: login/lock screen, Dock, Control Center, Spotlight overlays.
    public static let systemExcludedApps: [String] = [
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.apple.screencaptureui",
        "com.apple.ScreenSaver.Engine",
        "com.apple.UserNotificationCenter",
    ]

    public static func defaults(defaultInputSource: String?) -> Config {
        Config(defaultInputSource: defaultInputSource)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Config.currentVersion
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        rememberLastInputSource = try container.decodeIfPresent(Bool.self, forKey: .rememberLastInputSource) ?? true
        defaultInputSource = try container.decodeIfPresent(String.self, forKey: .defaultInputSource)
        apps = try container.decodeIfPresent([String: String].self, forKey: .apps) ?? [:]
        excludedApps = try container.decodeIfPresent([String].self, forKey: .excludedApps)
            ?? Config.systemExcludedApps
    }
}

/// Persists the configuration as JSON. A corrupt file throws instead of being
/// replaced, so a bad edit never silently wipes the user's rules.
public struct ConfigStore {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MKbd")
    }

    public static var defaultURL: URL {
        defaultDirectory.appendingPathComponent("config.json")
    }

    public func load() throws -> Config? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public func loadOrCreate(defaultInputSource: String?) throws -> Config {
        if let config = try load() { return config }
        let config = Config.defaults(defaultInputSource: defaultInputSource)
        try save(config)
        return config
    }

    public func save(_ config: Config) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(config)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Input source last seen in each app. Kept separate from the user's config so
/// automatic learning never rewrites hand-written rules.
public struct Memory: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// bundle ID → input source ID
    public var apps: [String: String]

    public init(version: Int = Memory.currentVersion, apps: [String: String] = [:]) {
        self.version = version
        self.apps = apps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Memory.currentVersion
        apps = try container.decodeIfPresent([String: String].self, forKey: .apps) ?? [:]
    }
}

public struct MemoryStore {
    public let url: URL

    public init(url: URL = MemoryStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        ConfigStore.defaultDirectory.appendingPathComponent("memory.json")
    }

    public func load() throws -> Memory {
        guard FileManager.default.fileExists(atPath: url.path) else { return Memory() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Memory.self, from: data)
    }

    public func save(_ memory: Memory) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(memory)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
