import SwiftUI

@main
struct MKbdApp: App {
    @StateObject private var model = KeyboardModel()
    @StateObject private var keystrokes = KeystrokeMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model, keystrokes: keystrokes)
        } label: {
            MenuBarLabel(keystrokes: keystrokes)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var keystrokes: KeystrokeMonitor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.system(size: 11.5, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            if keystrokes.authorized {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(keystrokes.perMinute)")
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    Text("/分")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .help(keystrokes.authorized
              ? "最近一分钟击键 \(keystrokes.perMinute) 次"
              : "击键统计需要辅助功能权限；打开 MKbd 面板授权")
    }
}
