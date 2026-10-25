import AppKit
import Foundation
import KeyboardCore

struct AppInfo: Equatable {
    let bundleID: String
    let name: String
}

struct RuleItem: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let appName: String
    let sourceID: String
    let sourceName: String
    let available: Bool
}

@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var config = Config()
    @Published private(set) var memory = Memory()
    @Published private(set) var sources: [InputSource] = []
    @Published private(set) var currentSourceID: String?
    @Published private(set) var currentApp: AppInfo?
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var configError: String?
    @Published private(set) var loginItemEnabled = false

    private let configStore: ConfigStore
    private let memoryStore: MemoryStore
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sourceObserver: NSObjectProtocol?
    private var configTimer: Timer?
    private var applyWork: DispatchWorkItem?
    private var applyGeneration = 0
    private var lastSeenConfigData: Data?
    private var iconCache: [String: NSImage] = [:]

    private static let sourceNotification =
        Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged")
    /// Focus events land before the app finishes activating; give it a moment
    /// and retry once if the system puts its own choice back.
    private static let initialDelay: TimeInterval = 0.10

    var ownBundleID: String {
        Bundle.main.bundleIdentifier ?? "local.mkbd.MKbd"
    }

    init(configStore: ConfigStore = ConfigStore(), memoryStore: MemoryStore = MemoryStore()) {
        self.configStore = configStore
        self.memoryStore = memoryStore
        loadInitialState()
        startObservers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor in self?.applyToFrontmost(recordPrevious: false) }
        }
    }

    var currentSourceName: String {
        currentSourceID.map(sourceName) ?? "未知"
    }

    var isCurrentAppExcluded: Bool {
        guard let bundleID = currentApp?.bundleID else { return false }
        return Resolver.isExcluded(bundleID: bundleID, config: config, ownBundleID: ownBundleID)
    }

    var ruleItems: [RuleItem] {
        config.apps.map { bundleID, sourceID in
            let available = sources.contains { $0.id == sourceID }
            return RuleItem(
                bundleID: bundleID,
                appName: AppNames.displayName(forBundleID: bundleID),
                sourceID: sourceID,
                sourceName: sourceName(sourceID),
                available: available
            )
        }
        .sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    }

    func sourceName(_ id: String) -> String {
        sources.first { $0.id == id }?.name ?? id
    }

    func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = icon
        return icon
    }

    func refreshPanel() {
        let latest = InputSources.enabled()
        if latest != sources { sources = latest }
        currentSourceID = InputSources.currentID()
    }

    // MARK: Settings

    func setEnabled(_ enabled: Bool) {
        if !enabled { cancelPendingApply() }
        updateConfig { $0.enabled = enabled }
        message = enabled ? "已启用自动切换" : "已暂停自动切换"
    }

    func setRemember(_ remember: Bool) {
        updateConfig { $0.rememberLastInputSource = remember }
        message = remember ? "将记住每个 App 的输入法" : "已关闭自动记忆"
    }

    func setDefaultSource(_ id: String?) {
        updateConfig { $0.defaultInputSource = id }
    }

    func setRule(bundleID: String, sourceID: String) {
        updateConfig { $0.apps[bundleID] = sourceID }
        message = "已为「\(AppNames.displayName(forBundleID: bundleID))」固定「\(sourceName(sourceID))」"
    }

    func removeRule(bundleID: String) {
        updateConfig { $0.apps.removeValue(forKey: bundleID) }
        message = "已删除「\(AppNames.displayName(forBundleID: bundleID))」的固定规则"
    }

    func setLoginItem(_ enabled: Bool) {
        do {
            try LoginAgent.setEnabled(enabled, executable: Bundle.main.executableURL?.path)
            message = enabled ? "已开启登录时自启" : "已关闭登录时自启"
        } catch {
            errorMessage = "设置登录自启失败：\(error.localizedDescription)"
            EventLog.write("设置登录自启失败：\(error.localizedDescription)")
        }
        loginItemEnabled = LoginAgent.isEnabled(executable: Bundle.main.executableURL?.path)
    }

    func reloadConfig() {
        lastSeenConfigData = nil
        pollConfigFile()
    }

    func openConfig() {
        ensureConfigFile()
        guard FileManager.default.fileExists(atPath: configStore.url.path) else { return }
        NSWorkspace.shared.open(configStore.url)
    }

    func revealConfig() {
        ensureConfigFile()
        guard FileManager.default.fileExists(atPath: configStore.url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([configStore.url])
    }

    func openLog() {
        let manager = FileManager.default
        if !manager.fileExists(atPath: EventLog.url.path) {
            manager.createFile(atPath: EventLog.url.path, contents: nil,
                               attributes: [.posixPermissions: 0o600])
        }
        NSWorkspace.shared.open(EventLog.url)
    }

    // MARK: Focus handling

    private func startObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            Task { @MainActor in self?.applicationActivated(app) }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyToFrontmost(recordPrevious: false) }
        })
        sourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.sourceNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.currentSourceID = InputSources.currentID() }
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollConfigFile() }
        }
        RunLoop.main.add(timer, forMode: .common)
        configTimer = timer
    }

    private func applicationActivated(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        let latest = InputSources.enabled()
        if latest != sources { sources = latest }
        currentSourceID = InputSources.currentID()
        guard Resolver.shouldApply(bundleID: bundleID, config: config, ownBundleID: ownBundleID) else {
            return
        }
        // Allow a manual choice inside the same app to stick until focus leaves.
        guard currentApp?.bundleID != bundleID else { return }

        if let previous = currentApp?.bundleID, config.rememberLastInputSource,
           let source = currentSourceID, sources.contains(where: { $0.id == source }) {
            remember(source, for: previous)
        }
        currentApp = Self.appInfo(app)
        scheduleApply(for: bundleID, delay: Self.initialDelay)
    }

    private func applyToFrontmost(recordPrevious: Bool) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return }
        let latest = InputSources.enabled()
        if latest != sources { sources = latest }
        currentSourceID = InputSources.currentID()
        guard Resolver.shouldApply(bundleID: bundleID, config: config, ownBundleID: ownBundleID) else {
            return
        }
        let previous = currentApp?.bundleID
        if recordPrevious, let previous, previous != bundleID,
           config.rememberLastInputSource, let source = currentSourceID {
            remember(source, for: previous)
        }
        currentApp = Self.appInfo(app)
        scheduleApply(for: bundleID, delay: Self.initialDelay)
    }

    private func scheduleApply(for bundleID: String, delay: TimeInterval) {
        cancelPendingApply()
        let generation = applyGeneration
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.apply(bundleID: bundleID, generation: generation, attempt: 0)
            }
        }
        applyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingApply() {
        applyWork?.cancel()
        applyWork = nil
        applyGeneration += 1
    }

    private func apply(bundleID: String, generation: Int, attempt: Int) {
        guard generation == applyGeneration, config.enabled else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }

        let latest = InputSources.enabled()
        if latest != sources { sources = latest }
        guard let target = Resolver.target(
            bundleID: bundleID, config: config, memory: memory,
            available: Set(latest.map(\.id))
        ) else { return }

        let current = InputSources.currentID()
        guard current != target else {
            currentSourceID = current
            return
        }

        let selected = InputSources.select(id: target)
        let after = InputSources.currentID()
        currentSourceID = after
        if selected, after == target {
            let appName = currentApp?.bundleID == bundleID ? (currentApp?.name ?? bundleID) : bundleID
            message = "已将「\(appName)」切换到「\(sourceName(target))」"
            EventLog.write("切换 \(bundleID) → \(target)")
            return
        }
        if attempt < 2 {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.apply(bundleID: bundleID, generation: generation, attempt: attempt + 1)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            errorMessage = "切换到「\(sourceName(target))」失败，请确认该输入法仍已启用。"
            EventLog.write("切换失败 \(bundleID) → \(target)（select=\(selected)，当前=\(after ?? "nil")）")
        }
    }

    private func remember(_ sourceID: String, for bundleID: String) {
        guard memory.apps[bundleID] != sourceID else { return }
        memory.apps[bundleID] = sourceID
        EventLog.write("记忆 \(bundleID) → \(sourceID)")
        do {
            try memoryStore.save(memory)
        } catch {
            EventLog.write("保存记忆失败：\(error.localizedDescription)")
            if errorMessage == nil {
                errorMessage = "保存输入法记忆失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: Loading and persistence

    private func loadInitialState() {
        let current = InputSources.currentID()
        do {
            let loaded: Config
            if let existing = try configStore.load() {
                loaded = existing
            } else {
                loaded = try configStore.loadOrCreate(defaultInputSource: current)
                message = "已创建配置文件"
            }
            config = loaded
            lastSeenConfigData = try? Data(contentsOf: configStore.url)
            configError = nil
        } catch {
            config = Config.defaults(defaultInputSource: current)
            configError = "配置文件无法解析：\(error.localizedDescription)"
            EventLog.write("配置加载失败：\(error.localizedDescription)")
        }

        do {
            memory = try memoryStore.load()
        } catch {
            memory = Memory()
            errorMessage = "读取输入法记忆失败：\(error.localizedDescription)"
        }

        sources = InputSources.enabled()
        currentSourceID = current
        currentApp = Self.appInfo(NSWorkspace.shared.frontmostApplication)
        loginItemEnabled = LoginAgent.isEnabled(executable: Bundle.main.executableURL?.path)
    }

    private func updateConfig(apply: Bool = true, _ change: (inout Config) -> Void) {
        guard configError == nil else { return }
        var next = config
        change(&next)
        guard next != config else { return }
        do {
            try configStore.save(next)
            config = next
            lastSeenConfigData = try? Data(contentsOf: configStore.url)
            if apply { applyToFrontmost(recordPrevious: false) }
        } catch {
            errorMessage = "保存配置失败：\(error.localizedDescription)"
            EventLog.write("保存配置失败：\(error.localizedDescription)")
        }
    }

    private func pollConfigFile() {
        let url = configStore.url
        guard let data = try? Data(contentsOf: url) else {
            if !FileManager.default.fileExists(atPath: url.path) {
                recreateMissingConfig()
            }
            return
        }
        guard data != lastSeenConfigData else { return }
        lastSeenConfigData = data
        do {
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            config = decoded
            configError = nil
            message = "已重新加载配置"
            EventLog.write("重新加载配置")
            applyToFrontmost(recordPrevious: false)
        } catch {
            configError = "配置文件无法解析：\(error.localizedDescription)"
            EventLog.write("配置解析失败：\(error.localizedDescription)")
        }
    }

    private func recreateMissingConfig() {
        var created = Config.defaults(defaultInputSource: InputSources.currentID())
        created.defaultInputSource = InputSources.currentID()
        do {
            try configStore.save(created)
            config = created
            lastSeenConfigData = try? Data(contentsOf: configStore.url)
            configError = nil
            message = "已重新创建配置文件"
        } catch {
            configError = "创建配置文件失败：\(error.localizedDescription)"
        }
    }

    private func ensureConfigFile() {
        guard !FileManager.default.fileExists(atPath: configStore.url.path) else { return }
        do {
            try configStore.save(config)
            lastSeenConfigData = try? Data(contentsOf: configStore.url)
        } catch {
            errorMessage = "创建配置文件失败：\(error.localizedDescription)"
        }
    }

    private static func appInfo(_ app: NSRunningApplication?) -> AppInfo? {
        guard let app, let bundleID = app.bundleIdentifier else { return nil }
        return AppInfo(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}

enum AppNames {
    static func displayName(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        return name
    }
}
