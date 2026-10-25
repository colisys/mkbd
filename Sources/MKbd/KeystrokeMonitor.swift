import AppKit
import ApplicationServices
import Foundation
import KeyboardCore

/// Global key-down monitoring for the menu-bar keystroke counter.
///
/// Global key events require the Accessibility (辅助功能) permission. The app
/// never prompts on its own: the panel's 授权 button triggers the system
/// prompt, and a one-second tick notices when the user grants it in System
/// Settings so the monitor can start without a restart.
@MainActor
final class KeystrokeMonitor: ObservableObject {
    @Published private(set) var perMinute = 0
    @Published private(set) var authorized = AXIsProcessTrusted()

    private var counter = KeystrokeCounter(window: 60)
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var tickTimer: Timer?

    init() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        if authorized { installMonitors() }
    }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        authorized = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if authorized { installMonitors() }
    }

    func openPrivacySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func installMonitors() {
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard !event.isARepeat else { return }
                Task { @MainActor in self?.record() }
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                if !event.isARepeat {
                    Task { @MainActor in self?.record() }
                }
                return event
            }
        }
    }

    private func record() {
        let now = ProcessInfo.processInfo.systemUptime
        counter.record(at: now)
        let value = counter.count(now: now)
        if value != perMinute { perMinute = value }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        counter.prune(now: now)
        let value = counter.count(now: now)
        if value != perMinute { perMinute = value }

        // Permission can be granted while the app is running.
        guard !authorized else { return }
        if AXIsProcessTrusted() {
            authorized = true
            installMonitors()
        }
    }
}
