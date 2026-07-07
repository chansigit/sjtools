# GTime — macOS 菜单栏世界时钟 设计文档

日期:2026-07-06 · 状态:已确认(用户批准)

## 目标

一个 macOS 菜单栏小工具,在顶栏常驻显示若干其他时区的当前时间,样式如:
`🇬🇧 7:11 AM⁺¹ 🇨🇳 2:11 PM⁺¹`(跨天带 ⁺¹/⁻¹ 上标)。
支持按城市名(中文/英文/拼音)搜索添加时区,支持开机自启。

## 用户确认的决定

- 技术方案:原生 Swift AppKit 应用(适配本机旧工具链 Swift 5.4 / SDK 11.3,零依赖)
- 时间格式:默认 12 小时制 AM/PM,菜单内可切换 24 小时制
- 首次启动:空白列表,菜单栏显示 🌐,由用户自行搜索添加

## 架构

```
gtime/
├── Sources/GTimeCore.swift   # 纯逻辑:模型、城市库、搜索、格式化(可测)
├── Sources/main.swift        # AppKit 壳:状态栏、菜单、搜索窗口、自启管理
├── Tests/main.swift          # 独立测试二进制(自带断言,不依赖 XCTest)
└── build.sh                  # 编译 → 打包 GTime.app → ad-hoc 签名 → 安装启动
```

### GTimeCore(纯逻辑层)

- `City`:内置约 200+ 主要城市(英文名、中文名、国家中英名、国旗 emoji、IANA 时区 ID)
- `TimeEntry`(Codable):用户已添加的条目,存 UserDefaults(JSON)
- `dayOffset(now:tz:local:)`:目标时区日历日 − 本地日历日(结果 ∈ {-1,0,+1})
- `timeString` / `statusText`:菜单栏文本合成;空列表 → "🌐"
- `searchCities(query)`:匹配中文名、英文名、国家名、拼音(CFStringTransform 生成)、
  IANA 标识符;前缀匹配优先于包含匹配;未收录城市可直接搜 443 个 IANA 时区 ID

### 应用壳(AppKit)

- `NSStatusItem`,attributedTitle 用等宽数字字体防抖动
- `NSMenu`:每城市一行(旗帜+城市+时间+日期,子菜单:移除/上移/下移)、
  添加城市…、24 小时制开关、登录时启动开关、退出
- 搜索窗口:`NSPanel` + `NSSearchField` + `NSTableView`,回车/双击添加
- 刷新:Timer 对齐分钟边界(RunLoop .common);监听系统唤醒、时钟与时区变更通知
- 单实例守护:检测同 bundle id 的已运行实例则退出

### 开机自启

`~/Library/LaunchAgents/com.sijie.gtime.plist`(RunAtLoad,指向
/Applications/GTime.app 内二进制)。首次运行默认写入;菜单可开关(写入/删除 plist)。
不用 SMAppService(需 macOS 13 SDK,本机 SDK 过旧)。

### 错误处理

- 无效时区 ID:条目跳过不崩溃
- LaunchAgent 写入失败:菜单开关回显真实状态
- 城市库在测试中全量校验:每个 tzID 必须能被系统 TimeZone 解析

## 测试策略

独立测试二进制(Tests/main.swift 与 GTimeCore.swift 共同编译),覆盖:
日期偏移(+1/0/−1 各场景)、12/24h 格式化、状态栏文本合成、
中文/英文/拼音/IANA 搜索与排序、持久化编解码、城市库全量 tzID 校验。
GUI 层(菜单/窗口)以手动运行 + 截图验证。
