# GTime

macOS 菜单栏小工具:世界时钟 + 鼠标/触控板滚动方向控制。

## 世界时钟

在顶栏常驻显示其他时区的当前时间,样式如
`🇬🇧 7:11 AM⁺¹  🇨🇳 2:11 PM⁺¹`(⁺¹/⁻¹ 表示相对本地日期的跨天)。

- 按城市名搜索添加时区,支持**中文 / 英文 / 拼音**(如 `北京`、`Tokyo`、`xianggang`),
  内置 200+ 主要城市,也可直接搜任意 IANA 时区标识符
- 内置库找不到的中小城市/任意地名(如 `达姆施塔特`、`Darmstadt`、大学、地标),
  可点搜索框里的「🔍 在线搜索」用系统地图数据联网解析出所在时区(无需任何权限)
- 时间随本地时钟自动换算,自动处理夏令时;睡眠唤醒、修改系统时间/时区后立即校正

## 滚动方向

macOS 只有一个全局「自然滚动」开关同时管鼠标和触控板。本功能通过事件拦截
把两者解耦,可**分别**把鼠标、触控板设为「自然」或「反转」。

- 菜单「滚动方向」子菜单里各自切换,✓ 标出当前方向(即监测状态)
- 会读取系统「自然滚动」作为基准自动换算,改了系统设置也保持正确
- 两个设备都无需翻转时不启用拦截,零开销
- 首次启用需授予**辅助功能**权限(事件拦截必需);菜单会引导到系统设置
- 局限:Magic Mouse 上报连续事件,会被当作触控板处理;普通滚轮鼠标正常

> 灵感与技术源自同仓库外的 [fanguolai](https://github.com/chansigit/fanguolai)(CLI 版)。

## 其它

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
| 滚动方向 ▸ | 鼠标 / 触控板 各自「自然 / 反转」;含系统基准显示与授权入口 |
| 登录时自动启动 | 开关 `~/Library/LaunchAgents/com.sijie.gtime.plist` |

## 卸载

```sh
pkill -x GTime
rm -rf /Applications/GTime.app ~/Library/LaunchAgents/com.sijie.gtime.plist
defaults delete com.sijie.gtime
```

## 开发

- `Sources/GTimeCore.swift` — 纯逻辑:时区数学、格式化、城市库与搜索(全部有测试)
- `Sources/ScrollCore.swift` — 纯逻辑:滚动翻转计算、delta 取负、设置持久化(全部有测试)
- `Sources/ScrollFlip.swift` — CGEventTap 控制器、辅助功能检查、系统基准读取
- `Sources/main.swift` — AppKit 壳:状态栏、菜单、搜索窗口、LaunchAgent
- `Tests/main.swift` — 独立测试二进制:
  `swiftc Sources/GTimeCore.swift Sources/ScrollCore.swift Tests/main.swift -o build/tests && ./build/tests`

兼容旧工具链(Swift 5.4 / macOS 11.3 SDK)编译,运行于 macOS 11+。
