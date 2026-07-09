# GTime: Dock 固定 + 显示器亮度 设计文档

日期:2026-07-08 · 状态:已确认(用户批准)

把两个已有小工具的能力并入 gtime 菜单栏应用:
- Dock 固定(参考 `/Users/chensijie/Projects/dockpin`)
- 显示器亮度(参考截图里的 MonitorControl 式面板;只做亮度,不做音量)

## Feature A — Dock 固定

### 目标
多显示器下 macOS 会把 Dock 跟着鼠标移到任意屏幕。让用户在菜单里看到 Dock
固定在哪块屏幕,并可选择固定到别的屏幕。

### 机制(移植自 dockpin)
鼠标移动事件的 `CGEventTap`(`.cghidEventTap`,mouseMoved/leftDragged/rightDragged)。
当光标接近**非目标**显示器的 Dock 触发边(下/左/右,由
`defaults read com.apple.dock orientation` 得出)时,把光标钳制到边缘外几像素,
使 Dock 无法在该屏激活 —— Dock 只能出现在目标屏。与滚动功能共用辅助功能权限。

### 菜单
```
Dock 固定 ▸
   关闭(不固定)          (单选,✓ 当前选择)
   内建 Color LCD (主)
   BenQ EW3270U
   LS32A70
   ──────
   Dock 当前在:…          (只读;能取到才显示)
   授予辅助功能权限…       (需要时出现)
```

### 持久化
按显示器**名称**(NSScreen.localizedName)存 UserDefaults(`dockPinTarget`);
启动时按名称解析回 displayID 再应用。名称找不到(拔了那块屏)则不固定。

### 代码
- `Sources/DockCore.swift`(纯逻辑,可测):`DockEdge`、`dockEdge(from:)`、
  `clampedCursor(point:displayBounds:isTargetDisplay:dockEdge:zone:)`
- `Sources/DockPin.swift`(仅 app):事件 tap 控制器、显示器枚举(CG + NSScreen 名称)、
  Dock 当前所在屏检测
- `Sources/main.swift`:「Dock 固定」子菜单与接线

## Feature B — 显示器亮度

### 目标
菜单里每块显示器一个亮度滑块,直接调硬件亮度。只做亮度。

### 机制
- 内建屏:私有 `DisplayServices` 框架(`DisplayServicesGetBrightness/SetBrightness`,
  dlopen 动态取符号),Apple Silicon 上可靠
- 外接屏:DDC/CI,VCP `0x10`(亮度),走 Apple Silicon 的 `IOAVService` I²C 路径
  (与 m1ddc / MonitorControl 相同做法):按显示器顺序匹配 IORegistry 里的
  `DCPAVServiceProxy`,用 `IOAVServiceWriteI2C` 写 VCP
- 外接屏不响应 DDC 时标记为「不支持」,不伪造

### 菜单
```
显示器亮度 ▸
   内建 Color LCD   [滑块]      (NSSlider 放进 NSMenuItem.view)
   BenQ EW3270U     [滑块]
   LS32A70          [滑块]      (不支持则显示灰字)
```
滑块拖动即时写亮度。启动时尽量读当前亮度作为初值(DDC 读失败则取中值/上次值)。
无需辅助功能权限。

### 代码
- `Sources/Brightness.swift`(仅 app):DisplayServices 动态绑定、IOAVService DDC 写、
  显示器→AVService 匹配、`BrightnessController`
- `Sources/main.swift`:「显示器亮度」子菜单(自定义滑块菜单项)

## 测试
- DockCore 钳制数学:目标屏不钳制、各边缘近/远、方向解析 —— 单测
- 亮度:VCP 数据帧构造(百分比→0..100 字节、校验和)等纯部分可单测;
  真实 DDC 写与滑块 UI —— 手动运行 + 实机(BenQ/三星已接)验证
- Dock:钳制逻辑单测;真实光标行为 —— 手动验证

## 已知限制
- DDC/CI 并非所有显示器/转接都支持
- Dock 当前所在屏检测依赖窗口列表,较新 macOS 可能需要屏幕录制权限;取不到则隐藏该行
- 显示器名称重复时按第一块匹配
