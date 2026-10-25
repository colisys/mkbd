# MKbd

macOS 菜单栏输入法自动切换工具。按 **App（bundle ID）** 记住上次使用的输入法，回到该 App 时自动恢复；也可以按配置文件为指定 App 固定输入法。

MKbd 只切换系统已经启用的输入法，不修改输入法列表，不需要辅助功能（Accessibility）权限。

## 功能

- 每个 App 独立记忆：离开 App 时记录当前输入法，切换回来时恢复。
- 固定规则优先：在面板或配置文件里为某个 App 指定输入法，之后始终使用它。
- 默认输入法：没有固定规则、也没有记忆时使用，例如新安装的 App。
- 配置文件热加载：手工编辑或 `mkbdctl` 修改配置后约 1 秒内生效，无需重启 App。
- 菜单栏面板显示当前聚焦的 App、真实 App 图标和当前输入法，可直接为当前 App 选择输入法。
- 菜单栏显示最近 60 秒的击键次数，按下按键即时更新，未授权辅助功能权限时显示 `—`。
- 排除系统界面：登录窗口、锁屏、Dock、控制中心、通知中心等默认不参与切换，列表可编辑。
- 可选登录时自启（用户级 LaunchAgent）。
- 事件日志：`~/Library/Logs/mkbd.log`，用于排查某次切换是否发生。

## 切换顺序

聚焦一个 App 时，MKbd 按以下顺序取第一个"已启用且存在"的输入法：

1. `apps[bundleID]`：配置文件中的固定规则。
2. `memory.json`：该 App 上次使用的输入法（`rememberLastInputSource` 开启时）。
3. `defaultInputSource`：默认输入法。
4. 以上都不可用时不切换。

已在排除列表中的 App 以及 MKbd 自身会被完全忽略。

## 击键统计与权限

- 菜单栏图标右侧的数字是最近 60 秒的按键次数：按一次键即时刷新，之后每秒随窗口滑动衰减。
- 只统计 `keyDown`，不计长按产生的自动重复；不记录按下的具体按键，计数只存在于内存中。
- 全局按键监听需要 **辅助功能** 权限。首次使用点击面板里的「授权统计」，在 **系统设置 → 隐私与安全性 → 辅助功能** 中勾选 MKbd；授权后约 1 秒内自动开始计数，不必重启。
- 未授权时菜单栏显示 `—`，输入法自动切换不受影响。旁边的齿轮按钮可以直接打开辅助功能设置。
- 重新打包会改变 ad-hoc 签名，macOS 可能要求重新授权。如果已勾选但菜单栏仍是 `—`，退出并重开 MKbd，或在辅助功能列表中移除 MKbd 后重新添加。

## 配置

配置文件：`~/Library/Application Support/MKbd/config.json`（首次运行自动创建，权限 600）。

```json
{
  "version": 1,
  "enabled": true,
  "rememberLastInputSource": true,
  "defaultInputSource": "com.apple.keylayout.ABC",
  "apps": {
    "com.apple.Terminal": "com.apple.keylayout.ABC",
    "com.tencent.xinWeChat": "com.apple.inputmethod.SCIM.ITABC"
  },
  "excludedApps": [
    "com.apple.loginwindow",
    "com.apple.SecurityAgent",
    "com.apple.dock",
    "com.apple.controlcenter",
    "com.apple.notificationcenterui",
    "com.apple.WindowManager",
    "com.apple.systemuiserver",
    "com.apple.screencaptureui",
    "com.apple.ScreenSaver.Engine",
    "com.apple.UserNotificationCenter"
  ]
}
```

- `apps` 的键是 App 的 bundle ID，值是输入法的 source ID（用 `mkbdctl list` 查看）。
- `defaultInputSource` 省略或为 `null` 表示"不切换"。
- 配置解析失败时 MKbd 保留上次可用的设置并在面板显示错误，不会覆盖你的文件；修好后点"重新加载配置"即可。
- 运行时记忆单独保存在 `~/Library/Application Support/MKbd/memory.json`，自动学习不会改写手写规则。

## CLI

`mkbdctl` 随 App 一起打包，位于 `MKbd.app/Contents/MacOS/mkbdctl`。

```sh
mkbdctl list                         # 已启用的输入法（ID 与名称）
mkbdctl current                      # 当前输入法
mkbdctl apps                         # 正在运行的 App 及其 bundle ID
mkbdctl status                       # 自动切换设置与配置文件位置
mkbdctl rules                        # 固定规则
mkbdctl set com.apple.finder com.apple.keylayout.ABC
mkbdctl unset com.apple.finder
mkbdctl switch com.apple.keylayout.ABC   # 立即切换
mkbdctl default com.apple.keylayout.ABC  # 设置默认输入法；none 表示不切换
mkbdctl remember on|off
mkbdctl enable|disable
```

CLI 只修改配置文件；正在运行的 App 会自动热加载，不需要重启。不要同时从面板和 CLI 保存，后写入的一方会覆盖。

## 构建与运行

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh scripts/build-app.sh --adhoc-sign
open dist/MKbd.app
```

产物是 `dist/MKbd.app`（菜单栏 App，`LSUIElement`，无 Dock 图标）。可以把整个 App 拖到"应用程序"目录；登录自启的 LaunchAgent 会记录当前可执行文件路径，移动后重新勾选一次即可。

不需要签名也能在本机运行；`--adhoc-sign` 只用于让每次重新打包后的 App 保持稳定的 ad-hoc 身份。

## 开发

- `Sources/KeyboardCore`：Carbon 输入法枚举与切换、配置 / 记忆 JSON 存储、切换决策、滚动击键计数、LaunchAgent、日志。
- `Sources/MKbd`：`MenuBarExtra` 面板、聚焦监听、配置热加载、全局击键监听。
- `Sources/mkbdctl`：命令行工具。
- `Tests/KeyboardCoreTests`：切换顺序、配置容错、权限位、固定规则、登录自启与击键窗口。

```sh
swift build
swift test
```

## 说明与限制

- 只支持菜单栏运行，macOS 13 及以上；已在 macOS 14（Intel）验证。未在 Apple Silicon 上实机验证。
- 切换粒度是 App（bundle ID），不是窗口或标签页。
- 系统设置里的「自动切换到文稿的输入法」会在文稿层面覆盖输入法选择；如果切换后立刻被改回去，可在 **系统设置 → 键盘 → 输入法 → 编辑…** 关闭该选项。
- 密码输入框等安全输入由系统接管，MKbd 不干预；安全输入期间全局击键可能也不会计数。
- 击键统计只保存时间戳计数，不保存按键内容，也不写入日志。
- 输入法切换通过 Carbon `TISSelectInputSource` 完成，只对已加入系统输入法列表并启用的 source 生效；被移除的规则会在界面标记为不可用并自动回退到下一候选。
- 配置与记忆文件只保存在本机，不上传任何内容。

## 许可证

MIT，见 [`LICENSE`](LICENSE)。
