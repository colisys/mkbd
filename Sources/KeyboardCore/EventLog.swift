import Foundation

/// Minimal append-only log for diagnosing focus and switching decisions.
public enum EventLog {
    public static let maxBytes = 512 * 1024

    public static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/mkbd.log")
    }

    private static let queue = DispatchQueue(label: "local.mkbd.log")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    public static func write(_ message: String) {
        queue.async {
            let line = "\(formatter.string(from: Date()))  \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let manager = FileManager.default
            let directory = url.deletingLastPathComponent()
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            if let attributes = try? manager.attributesOfItem(atPath: url.path),
               let size = (attributes[.size] as? NSNumber)?.intValue, size > maxBytes {
                try? manager.removeItem(at: url)
            }
            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil,
                                   attributes: [.posixPermissions: 0o600])
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
