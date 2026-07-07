# GTime

macOS 菜单栏世界时钟:在顶栏常驻显示其他时区的当前时间,样式如
`🇬🇧 7:11 AM⁺¹  🇨🇳 2:11 PM⁺¹`(⁺¹/⁻¹ 表示相对本地日期的跨天)。

- 按城市名搜索添加时区,支持**中文 / 英文 / 拼音**(如 `北京`、`Tokyo`、`xianggang`),
  内置 200+ 主要城市,也可直接搜任意 IANA 时区标识符
- 内置库找不到的中小城市/任意地名(如 `达姆施塔特`、`Darmstadt`、大学、地标),
  可点搜索框里的「🔍 在线搜索」用系统地图数据联网解析出所在时区(无需任何权限)
- 时间随本地时钟自动换算,自动处理夏令时;睡眠唤醒、修改系统时间/时区后立即校正
- 默认开机自动启动(菜单内可关)
- 纯 AppKit 原生实现,零依赖,无 Dock 图标,内存占用极小

## 构建与安装

```sh
./build.sh
```

脚本会依次:跑测试 → 编译 → 打包 `GTime.app` → ad-hoc 签名 → 安装到
`/Applications`(不可写时装到 `~/Applications`)→ 启动。

## 使用

点击菜单栏的时间(或 🌐)打开菜单:

| 菜单项 | 说明 |
|---|---|
| 城市条目 | 显示该地当前时间与日期;子菜单可 **移除 / 上移 / 下移** |
| 添加城市… | 打开搜索窗口,回车或双击添加,Esc 关闭;本地无结果时回车走在线搜索 |
| 24 小时制 | 切换 12/24 小时显示 |
| 登录时自动启动 | 开关 `~/Library/LaunchAgents/com.sijie.gtime.plist` |

## 卸载

```sh
pkill -x GTime
rm -rf /Applications/GTime.app ~/Library/LaunchAgents/com.sijie.gtime.plist
defaults delete com.sijie.gtime
```

## 开发

- `Sources/GTimeCore.swift` — 纯逻辑:时区数学、格式化、城市库与搜索(全部有测试)
- `Sources/main.swift` — AppKit 壳:状态栏、菜单、搜索窗口、LaunchAgent
- `Tests/main.swift` — 独立测试二进制:`swiftc Sources/GTimeCore.swift Tests/main.swift -o build/tests && ./build/tests`

兼容旧工具链(Swift 5.4 / macOS 11.3 SDK)编译,运行于 macOS 11+。
