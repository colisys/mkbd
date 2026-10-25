import AppKit
import Foundation
import KeyboardCore

setvbuf(stdout, nil, _IOLBF, 0)

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let usage = """
用法: mkbdctl <命令>
  list                     列出已启用的输入法（ID 与名称）
  current                  显示当前输入法
  status                   显示自动切换设置
  apps                     列出正在运行的 App 及其 bundle ID
  rules                    列出固定规则
  set <bundle-id> <输入法ID>  为 App 固定输入法
  unset <bundle-id>        删除固定规则
  switch <输入法ID>         立即切换当前输入法
  default [输入法ID]        查看或设置默认输入法；设为 none 表示不切换
  remember on|off          打开或关闭“记住上次输入法”
  enable|disable           打开或关闭自动切换
  config                   打印配置文件路径
"""

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage, code: 2) }
let rest = Array(arguments.dropFirst())

let store = ConfigStore()
let sources = InputSources.enabled()

func sourceLabel(_ id: String) -> String {
    if let source = sources.first(where: { $0.id == id }) {
        return "\(source.name)\t\(id)"
    }
    return "\(id)（不可用）"
}

func loadConfig() -> Config {
    do {
        if let config = try store.load() { return config }
        return try store.loadOrCreate(defaultInputSource: InputSources.currentID())
    } catch {
        fail("读取配置失败：\(error.localizedDescription)\n配置文件：\(store.url.path)")
    }
}

func save(_ config: Config) {
    do {
        try store.save(config)
    } catch {
        fail("保存配置失败：\(error.localizedDescription)")
    }
}

func requireSource(_ id: String) -> String {
    guard sources.contains(where: { $0.id == id }) else {
        let available = sources.map { "  \($0.id)\t\($0.name)" }.joined(separator: "\n")
        fail("未知或未启用的输入法：\(id)\n可用输入法：\n\(available)")
    }
    return id
}

switch command {
case "list":
    if sources.isEmpty {
        print("没有已启用的输入法")
    } else {
        for source in sources {
            print("\(source.id)\t\(source.name)")
        }
    }

case "current":
    guard let current = InputSources.current() else { fail("无法读取当前输入法") }
    print("\(current.id)\t\(current.name)")

case "status":
    let config = loadConfig()
    let current = InputSources.current()
    print("自动切换: \(config.enabled ? "已启用" : "已暂停")")
    print("记住上次输入法: \(config.rememberLastInputSource ? "是" : "否")")
    print("默认输入法: \(config.defaultInputSource.map(sourceLabel) ?? "不切换")")
    print("固定规则: \(config.apps.count) 条")
    print("当前输入法: \(current.map { "\($0.name)\t\($0.id)" } ?? "未知")")
    print("配置文件: \(store.url.path)")

case "apps":
    let apps = NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    for app in apps {
        print("\(app.bundleIdentifier ?? "")\t\(app.localizedName ?? "")")
    }

case "rules":
    let config = loadConfig()
    if config.apps.isEmpty {
        print("没有固定规则")
    } else {
        for (bundleID, sourceID) in config.apps.sorted(by: { $0.key < $1.key }) {
            print("\(bundleID)\t\(sourceLabel(sourceID))")
        }
    }

case "set":
    guard rest.count == 2 else { fail("用法: mkbdctl set <bundle-id> <输入法ID>", code: 2) }
    let bundleID = rest[0]
    let sourceID = requireSource(rest[1])
    var config = loadConfig()
    config.apps[bundleID] = sourceID
    save(config)
    print("已固定 \(bundleID) → \(sourceLabel(sourceID))")

case "unset":
    guard rest.count == 1 else { fail("用法: mkbdctl unset <bundle-id>", code: 2) }
    var config = loadConfig()
    guard config.apps.removeValue(forKey: rest[0]) != nil else {
        print("\(rest[0]) 没有固定规则")
        exit(0)
    }
    save(config)
    print("已删除 \(rest[0]) 的固定规则")

case "switch":
    guard rest.count == 1 else { fail("用法: mkbdctl switch <输入法ID>", code: 2) }
    let sourceID = requireSource(rest[0])
    guard InputSources.select(id: sourceID), InputSources.currentID() == sourceID else {
        fail("切换到 \(sourceLabel(sourceID)) 失败")
    }
    print("当前输入法：\(sourceLabel(sourceID))")

case "default":
    if rest.isEmpty {
        let config = loadConfig()
        print(config.defaultInputSource.map(sourceLabel) ?? "不切换")
    } else if rest.count == 1 {
        var config = loadConfig()
        if rest[0] == "none" || rest[0] == "-" {
            config.defaultInputSource = nil
            save(config)
            print("默认输入法：不切换")
        } else {
            let sourceID = requireSource(rest[0])
            config.defaultInputSource = sourceID
            save(config)
            print("默认输入法：\(sourceLabel(sourceID))")
        }
    } else {
        fail("用法: mkbdctl default [输入法ID|none]", code: 2)
    }

case "remember":
    guard rest.count == 1, rest[0] == "on" || rest[0] == "off" else {
        fail("用法: mkbdctl remember on|off", code: 2)
    }
    var config = loadConfig()
    config.rememberLastInputSource = rest[0] == "on"
    save(config)
    print("记住上次输入法：\(config.rememberLastInputSource ? "已开启" : "已关闭")")

case "enable", "disable":
    var config = loadConfig()
    config.enabled = command == "enable"
    save(config)
    print("自动切换：\(config.enabled ? "已启用" : "已暂停")")

case "config":
    print(store.url.path)

case "help", "-h", "--help":
    print(usage)

default:
    fail(usage, code: 2)
}
