import AppKit
import KeyboardCore
import SwiftUI

struct MenuPanel: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject var keystrokes: KeystrokeMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    currentAppCard
                    options
                    Divider()
                    rulesSection
                    statusMessage
                }
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { model.refreshPanel() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("MKbd", systemImage: "keyboard").font(.headline)
            Spacer()
            Circle()
                .fill(model.config.enabled ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
                .help(model.config.enabled ? "自动切换已启用" : "自动切换已暂停")
                .accessibilityLabel(model.config.enabled ? "自动切换已启用" : "自动切换已暂停")
            Toggle("启用自动切换", isOn: Binding(
                get: { model.config.enabled },
                set: { model.setEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("启用或暂停自动切换")
            .disabled(model.configError != nil)
        }
    }

    private var currentAppCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("当前 App").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(model.currentApp?.bundleID ?? "—")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 10) {
                currentAppIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.currentApp?.name ?? "未识别")
                        .font(.callout.weight(.semibold)).lineLimit(1)
                    Text(model.currentSourceName)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(model.config.enabled ? "自动" : "已暂停")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(model.config.enabled ? Color.green : Color.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((model.config.enabled ? Color.green : Color.secondary).opacity(0.14),
                                in: Capsule())
            }
            HStack(spacing: 8) {
                Text("此 App 使用").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("此 App 使用的输入法", selection: ruleSelection) {
                    Text("自动").tag("")
                    ForEach(model.sources) { source in
                        Text(source.name).tag(source.id)
                    }
                    if let bundleID = model.currentApp?.bundleID,
                       let rule = model.config.apps[bundleID],
                       !model.sources.contains(where: { $0.id == rule }) {
                        Text("\(rule)（不可用）").tag(rule)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 190)
                .disabled(model.currentApp == nil || model.isCurrentAppExcluded || model.configError != nil)
                .help("自动：优先使用记忆，其次默认输入法；固定后始终使用所选输入法")
            }
            if model.isCurrentAppExcluded {
                Text("该 App 在排除列表中，MKbd 不会切换它。")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var currentAppIcon: some View {
        if let bundleID = model.currentApp?.bundleID,
           let icon = model.icon(forBundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("记住每个 App 上次使用的输入法", isOn: Binding(
                get: { model.config.rememberLastInputSource },
                set: { model.setRemember($0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .help("切换回来时恢复上次在该 App 中使用过的输入法；固定规则优先")
            .disabled(model.configError != nil)

            HStack(spacing: 8) {
                Text("默认输入法").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("默认输入法", selection: Binding(
                    get: { model.config.defaultInputSource ?? "" },
                    set: { model.setDefaultSource($0.isEmpty ? nil : $0) }
                )) {
                    Text("不切换").tag("")
                    ForEach(model.sources) { source in
                        Text(source.name).tag(source.id)
                    }
                    if let id = model.config.defaultInputSource,
                       !model.sources.contains(where: { $0.id == id }) {
                        Text("\(id)（不可用）").tag(id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 170)
                .disabled(model.configError != nil)
                .help("没有固定规则和记忆时使用")
            }

            HStack(spacing: 8) {
                Label("每分钟击键", systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if keystrokes.authorized {
                    Text("\(keystrokes.perMinute) 次/分")
                        .font(.caption.monospacedDigit())
                        .help("最近 60 秒的按键次数，随击键即时更新")
                } else {
                    Button("授权统计") { keystrokes.requestPermission() }
                        .controlSize(.small)
                        .help("全局击键统计需要辅助功能权限")
                    Button {
                        keystrokes.openPrivacySettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("打开系统设置 › 隐私与安全性 › 辅助功能")
                    .accessibilityLabel("打开辅助功能设置")
                }
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("固定规则").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.ruleItems.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if model.ruleItems.isEmpty {
                Text("还没有固定规则。为上方 App 选择输入法即可添加；其余 App 使用记忆或默认值。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.ruleItems) { item in
                        RuleRow(
                            item: item,
                            icon: model.icon(forBundleID: item.bundleID),
                            sources: model.sources,
                            set: { model.setRule(bundleID: item.bundleID, sourceID: $0) },
                            remove: { model.removeRule(bundleID: item.bundleID) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let error = model.configError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let message = model.message {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("登录时自启", isOn: Binding(
                get: { model.loginItemEnabled },
                set: { model.setLoginItem($0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            Spacer()
            Menu {
                Button("打开配置文件") { model.openConfig() }
                Button("在 Finder 中显示") { model.revealConfig() }
                Button("重新加载配置") { model.reloadConfig() }
                Divider()
                Button("打开日志") { model.openLog() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("配置文件与日志")
            .accessibilityLabel("配置文件与日志")
            Button("退出") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
    }

    private var ruleSelection: Binding<String> {
        Binding(
            get: {
                guard let bundleID = model.currentApp?.bundleID else { return "" }
                return model.config.apps[bundleID] ?? ""
            },
            set: { sourceID in
                guard let bundleID = model.currentApp?.bundleID else { return }
                if sourceID.isEmpty {
                    model.removeRule(bundleID: bundleID)
                } else {
                    model.setRule(bundleID: bundleID, sourceID: sourceID)
                }
            }
        )
    }
}

private struct RuleRow: View {
    let item: RuleItem
    let icon: NSImage?
    let sources: [InputSource]
    let set: (String) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.appName).font(.caption.weight(.medium)).lineLimit(1)
                if item.appName != item.bundleID {
                    Text(item.bundleID)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(sources) { source in
                    Button(source.name) { set(source.id) }
                }
                if !item.available {
                    Divider()
                    Text("当前规则：\(item.sourceID)（不可用）")
                }
            } label: {
                Text(item.sourceName)
                    .font(.caption)
                    .foregroundStyle(item.available ? Color.primary : Color.red)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: 120, alignment: .trailing)
            .help("更改「\(item.appName)」的输入法")
            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("删除「\(item.appName)」的规则")
            .accessibilityLabel("删除「\(item.appName)」的规则")
        }
        .padding(8)
        .background(.quaternary.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
