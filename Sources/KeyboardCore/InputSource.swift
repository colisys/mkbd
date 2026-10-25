import Carbon
import Foundation

public struct InputSource: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case keyboardLayout
        case inputMethod
    }

    public let id: String
    public let name: String
    public let kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// Thin wrapper around the Carbon Text Input Source API. Switching does not
/// require Accessibility permission; the source must already be enabled in
/// System Settings.
public enum InputSources {
    /// Enabled and selectable sources, layouts first and then by name.
    public static func enabled() -> [InputSource] {
        let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        let list = TISCreateInputSourceList(filter, false).takeRetainedValue()
        var result: [InputSource] = []
        var seen = Set<String>()
        for index in 0..<CFArrayGetCount(list) {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: TISInputSource.self)
            guard boolProperty(source, kTISPropertyInputSourceIsEnabled),
                  boolProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  let id = stringProperty(source, kTISPropertyInputSourceID),
                  let name = stringProperty(source, kTISPropertyLocalizedName),
                  seen.insert(id).inserted else { continue }
            result.append(InputSource(id: id, name: name, kind: kind(of: source)))
        }
        return result.sorted {
            if $0.kind != $1.kind { return $0.kind == .keyboardLayout }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func enabledIDs() -> Set<String> {
        Set(enabled().map(\.id))
    }

    public static func current() -> InputSource? {
        guard let raw = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let id = stringProperty(raw, kTISPropertyInputSourceID),
              let name = stringProperty(raw, kTISPropertyLocalizedName) else { return nil }
        return InputSource(id: id, name: name, kind: kind(of: raw))
    }

    public static func currentID() -> String? {
        current()?.id
    }

    /// Selects an enabled source by ID. Returns false when the system rejected
    /// the request (for example the source was disabled or removed).
    ///
    /// The source is used while the owning CFArray is still alive: returning
    /// the unretained element and selecting after the array's lifetime ends
    /// crashes in optimized builds.
    public static func select(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        let list = TISCreateInputSourceList(filter, false).takeRetainedValue()
        guard CFArrayGetCount(list) > 0 else { return false }
        let source = unsafeBitCast(CFArrayGetValueAtIndex(list, 0), to: TISInputSource.self)
        let status = TISSelectInputSource(source)
        withExtendedLifetime(list) {}
        return status == noErr
    }

    private static func kind(of source: TISInputSource) -> InputSource.Kind {
        stringProperty(source, kTISPropertyInputSourceType) == (kTISTypeKeyboardLayout as String)
            ? .keyboardLayout
            : .inputMethod
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
}
