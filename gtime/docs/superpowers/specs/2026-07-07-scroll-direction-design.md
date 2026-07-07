# GTime 滚动方向控制 设计文档

日期:2026-07-07 · 状态:已确认(用户批准)

## 目标

在现有 gtime 菜单栏应用里加一个功能:独立监测并调节**鼠标**与**触控板**的
滚动方向(自然 / 反转)。macOS 只有一个全局「自然滚动」开关同时作用于两者,
本功能通过事件拦截把两个设备解耦,可分别设为自然或反转。参考项目
`/Users/chensijie/Projects/fanguolai`(CLI,用 CGEventTap 反转鼠标滚动而不影响触控板)。

## 用户确认的决定

- 位置:加进现有 gtime 菜单栏应用(同一菜单栏图标,时钟下方加「滚动方向」子菜单)
- 实现:菜单栏 app 内置事件拦截,完全自包含,不依赖外部 fanguolai CLI
- 滚动轴:只控制纵向(上下)滚动

## 核心机制(移植自 fanguolai)

会话级 `CGEventTap`(`.cgSessionEventTap`,`.headInsertEventTap`)挂在 AppKit
主 run loop 上,拦截 `scrollWheel` 事件:

- 设备判定:`scrollWheelEventIsContinuous` == 0 → 鼠标滚轮(离散);!= 0 → 触控板(连续)
- 对需要翻转的设备,复制事件并对纵向三个字段取负:
  `scrollWheelEventDeltaAxis1`、`scrollWheelEventPointDeltaAxis1`、
  `scrollWheelEventFixedPtDeltaAxis1`;其余原样透传
- `tapDisabledByTimeout` / `tapDisabledByUserInput` 时重新启用 tap

## 自然 / 反转模型

macOS 全局「自然滚动」开关在事件到达 tap **之前**就已对 delta 定号,因此:

```
设备实际方向 = 系统基准 XOR 本 app 对该设备的翻转
```

用户选择的是**绝对方向**(自然 / 反转)。app 读取系统基准
(`com.apple.swipescrolldirection`,通过 CFPreferences),对每个设备计算:
`flip = (期望方向 != 系统基准)`。这样即使之后改了系统开关,显示与效果仍正确。

性能:当两个设备都无需翻转(flip 均为 false)时停掉 tap,零开销;
有任一需要翻转时再创建 tap。

## 菜单(时钟下方新增「滚动方向」子菜单)

```
滚动方向 ▸
   🖱 鼠标 ▸       自然     / 反转   (单选,✓ 标当前)
   🖐 触控板 ▸     自然     / 反转
   ─────────
   系统自然滚动:开/关            (只读信息行,基准参考)
   授予辅助功能权限…             (仅在未授权 / tap 创建失败时出现)
```

✓ 即「监测」:一眼看到当前实际方向;点另一项即调节。默认两设备都为「自然」
(即不翻转,与系统一致),用户按需把某个设为「反转」。

## 权限与自启

- 事件 tap 需要辅助功能权限。首次启用翻转时用
  `AXIsProcessTrustedWithOptions(kAXTrustedCheckOptionPrompt=true)` 触发系统弹窗
- 未授权时 tap 创建失败:菜单显示「授予辅助功能权限…」,点击打开
  系统设置 › 隐私与安全性 › 辅助功能;授权后(app 激活 / 菜单打开时)自动重试
- 设置存 UserDefaults(`scrollMouseNatural`、`scrollTrackpadNatural`),启动时重新应用;
  现有 gtime LaunchAgent 已覆盖开机自启,无需单独守护进程

## 代码结构

- `Sources/ScrollCore.swift` — 纯逻辑,可单测:`ScrollSettings` 模型、
  `computeFlips(baselineNatural:)`、`shouldRunTap(...)`、纵向 delta 取负的纯函数。
  编入 app 与测试二进制
- `Sources/ScrollFlip.swift` — `CGEventTap` 控制器、辅助功能检查、系统基准读取、
  run loop 接线(仅编入 app)
- `Sources/main.swift` — 「滚动方向」子菜单与接线
- `build.sh` — 编译命令加入两个新文件(测试编译加 ScrollCore.swift)

## 测试策略

TDD 覆盖纯逻辑:
- `computeFlips`:baseline(自然/反转)× 期望(自然/反转)全组合 → 正确 flip 布尔
- `shouldRunTap`:两设备翻转布尔的所有组合
- delta 取负:给定 delta 与设备类型(连续/离散)+ flip → 输出 delta;
  只动纵向、不动横向、非目标设备不动
- 设置持久化编解码

tap 生命周期、权限弹窗、真实滚动效果 → 手动运行 + 截图验证。

## 已知限制

Magic Mouse 上报连续事件,会被判定为「触控板」(与 fanguolai 相同的局限)。
普通滚轮鼠标工作正常。文档中注明。
