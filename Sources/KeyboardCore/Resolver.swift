import Foundation

public enum Resolver {
    public static func shouldApply(bundleID: String, config: Config, ownBundleID: String) -> Bool {
        guard config.enabled, bundleID != ownBundleID else { return false }
        return !config.excludedApps.contains(bundleID)
    }

    public static func isExcluded(bundleID: String, config: Config, ownBundleID: String) -> Bool {
        bundleID == ownBundleID || config.excludedApps.contains(bundleID)
    }

    /// First usable candidate wins: explicit rule, then per-app memory, then
    /// the default. Unavailable input sources are skipped rather than applied.
    public static func target(
        bundleID: String,
        config: Config,
        memory: Memory,
        available: Set<String>
    ) -> String? {
        var candidates: [String?] = [config.apps[bundleID]]
        if config.rememberLastInputSource {
            candidates.append(memory.apps[bundleID])
        }
        candidates.append(config.defaultInputSource)
        for case let candidate? in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if available.contains(trimmed) { return trimmed }
        }
        return nil
    }
}
