# 在 macOS 上打开"系统 Wi-Fi 菜单":私有接口与可行方法实测

> 环境:macOS 27.2(26B123),arm64,主屏 1920×1243,真机验证。
> 目标:在点击菜单栏某个元素时,弹出 **macOS 自带的 Wi-Fi 菜单**(不是 NetBar 自己画的那一个)。

---

## 一、结论

| 结论 | 说明 |
| --- | --- |
| **不存在可直接调用的私有 API** | 系统私有框架里没有"打开 Wi-Fi 菜单"的入口;连二进制都不在磁盘上(见方法四) |
| **Accessibility 的 `AXShowMenu` / `AXPress` 在本机是空操作** | 调用返回 `err=0`,但菜单不会出现(见方法二) |
| **唯一可靠的方法:合成鼠标事件(CGEvent)真实点击菜单栏项目** | 已实测成功(见方法一),NetBar 已按此实现 |
| **需要"辅助功能"权限** | 定位元素和投递鼠标事件都要 TCC Accessibility 授权;没有私有接口能绕过 |

推荐实现已落地:[NBSystemWiFiMenu.h](../../NetBar/Bridge/NBSystemWiFiMenu.h) / [NBSystemWiFiMenu.m](../../NetBar/Bridge/NBSystemWiFiMenu.m)。

---

## 二、本机的菜单栏到底长什么样

菜单栏右侧的项目由 **`com.apple.MenuBarAgent`** 统一承载(不是 Control Center,也不是 SystemUIServer)。逐像素扫描菜单栏(每 2 px 用 `AXUIElementCopyElementAtPosition` 命中一次)得到的**完整清单**:

```
x=0    pid=64586 role='AXMenuBar'        (左边:当前 App 的菜单栏)
x=10   pid=64586 role='AXMenuBarItem'    (Apple 菜单)
x=1326 pid=1244  role='AXMenuBarItem'    (Shadowrocket)
x=1418 pid=785   role='drizzle'          (天气)
x=1486 pid=66791 role='AXMenuBarItem'    (AirBattery 90%)
x=1556 pid=799   role='AXMenuBarItem'    (Live Dashboard)
x=1588 pid=787   role='Squirrel - Sim…'  (输入法)
x=1632 pid=97220 role='吴同宇的iPhone'    (NetBar 自己)
x=1722 pid=673   role='Control Center'   (控制中心 / BentoBox)
x=1764 pid=673   role='Clock'            (时钟)
```

**关键事实:本机没有独立的 Wi-Fi 菜单栏项目**。Wi-Fi 控件在 **Control Center(BentoBox)项目的下拉菜单里**:

```
role='Control Center'  actions=AXShowMenu,AXPress        <- 菜单栏项目
  └─ Control Center 的下拉窗口
       └─ AXGroup (actions=AXShowMenu,AXPress)
            └─ role='Wi‐Fi: 吴同宇的iPhone'  actions=AXPress
```

(注:配置里 `NSStatusItem Visible WiFi = 1`,但扫描不到独立项目。macOS 27 把右侧状态项统一收进 MenuBarAgent 的一个窗口,Wi-Fi 是否单独显示由"控制中心"设置决定。)

---

## 三、方法逐一实测

### 方法一:合成鼠标事件(CGEvent)—— **推荐,已验证可用** ✅

用 Accessibility 只负责**找到元素的位置**,点击本身交给 `CGEventPost(kCGHIDEventTap, …)` 投递一对 `LeftMouseDown / LeftMouseUp`。

**证据**:点击 Control Center 项目中心 (1734, 19) 后,窗口列表里立刻多出系统菜单:

```console
--- BEFORE ---
  layer=24 owner='Menubar' rect=(0,0,1920x38)
--- AFTER-CLICK ---
  layer=101 owner='Control Center' name='Control Center' rect=(1440,0,656x972)   <- 菜单出现了
--- AFTER-ESC ---
  layer=24 owner='Menubar' rect=(0,0,1920x38)                                     <- Esc 关闭
```

**再点 Wi-Fi 磁贴**(Control Center 下拉里的 `Wi‐Fi: …` 项),就展开成真正的系统 Wi-Fi 菜单。用 AX 读它的内容可以确认:

```console
after: Known Networks=1 Other Networks=1 Personal Hotspot=2 Settings=1
  found "Known Networks"
  found "Other Networks"
  found "吴同宇的iPhone, Personal Hotspot, 3 bars"
  found "Personal Hotspot"
  found "Wi‐Fi Settings..."
SYSTEM WIFI MENU IS OPEN
```

- **权限**:辅助功能(TCC Accessibility)。
- **可靠性**:不依赖任何私有符号;菜单栏怎么改版都能通过 AX 描述重新定位。
- **代价**:指针会被移到菜单栏(这是必须的,因为菜单只认真实点击)。

### 方法二:AXUIElement 直接执行 `AXShowMenu` / `AXPress` —— **无效** ❌

这是最"正统"的无鼠标方案,但在本机**完全不起作用**:

| 目标元素 | 动作 | 返回值 | 结果 |
| --- | --- | --- | --- |
| MenuBarAgent 的 `Control Center` | `AXShowMenu` | `err=0` | 没有新窗口,菜单未打开 |
| MenuBarAgent 的 `Control Center` | `AXPress` | `err=0` | 同上 |
| MenuBarAgent 的 `Clock` | `AXPress` / `AXShowMenu` | `err=0` | 同上 |
| Control Center 下拉里的 Wi-Fi 磁贴及其父 AXGroup | `AXPress` | `err=0` | 子菜单未展开 |

判定方式:每次动作后对比 `CGWindowListCopyWindowInfo` 的窗口集合(含 layer≥100 的弹窗层),窗口数始终不变。

> 也就是说:`AXShowMenu` 会**谎报成功**。任何只检查返回值的实现都会"看起来对、实际没反应"。

`AXUIElementCopyElementAtPosition` 本身是好的——它精确返回了每个菜单栏项的角色、描述和 frame,所以本方案用它做**定位**,但**不用它做动作**。

### 方法三:AppleScript / System Events —— **不可行** ❌

```console
$ osascript -e 'tell application "System Events" to tell process "ControlCenter" to get every menu bar item of menu bar 2'
72:91: execution error: System Events got an error: A privilege violation occurred. (-10004)
```

需要"自动化(Automation)"+ 辅助功能双重授权,而且这条路子底层同样依赖 AX 动作。本机未授权,且不如方法一直接。

### 方法四:私有框架 —— **未找到可用入口** ❌

`/System/Library/PrivateFrameworks` 下确实存在:

```
ControlCenter.framework  MenuBarClient.framework  MenuBarClientCore.framework
SystemUIPlugin.framework  SkyLight.framework  CoreWiFi.framework  WiFiPolicy.framework
```

但它们的可执行文件**根本不在磁盘上**(在 dyld 共享缓存里,只剩 Resources 和 _CodeSignature):

```console
$ ls -la /System/Library/PrivateFrameworks/ControlCenter.framework/Versions/Current/
drwxr-xr-x  Resources
drwxr-xr-x  _CodeSignature
$ nm -gU .../ControlCenter   # 无文件,导不出任何符号
exported symbols: 0
```

因此:
- 没有可链接的私有符号(`nm` / `otool` 拿不到类与方法表);
- 也没有对外公开的 `showMenu` / `openWiFiMenu` 之类入口;
- 硬要做静态逆向需要先把 dyld 共享缓存抽出来,成本高,而且即便找到符号,未签名第三方进程调用系统私有类还会撞上 SIP / 签名校验。

**结论:这条路不划算,本方案不依赖任何私有 API。**

### 方法五:旧 Menu Extras(`AirPort.menu`)—— 未采用 ⚠️

`/System/Library/CoreServices/Menu Extras/` 里 `AirPort.menu` 等仍存在,但 SystemUIServer 已经不再加载它们:

```console
$ defaults read com.apple.systemuiserver
menuExtras = ( );        <- 空数组
```

新系统的菜单栏由 MenuBarAgent + Control Center 接管,旧机制不能用来弹 Wi-Fi 菜单。

---

## 四、推荐实现

已实现为 [NBSystemWiFiMenu](../../NetBar/Bridge/NBSystemWiFiMenu.m),算法:

```
openSystemWiFiMenu
  ├─ 未授予辅助功能权限? → 返回 NotPermitted(调用方去引导授权)
  ├─ 取 MenuBarAgent 的 AXExtrasMenuBar
  │    (依次尝试 com.apple.MenuBarAgent / controlcenter / systemuiserver,兼容旧系统)
  ├─ 第一优先:菜单栏里若有独立的 "Wi-Fi" 项 → 点它的中心,结束   ← 单击直达
  └─ 第二优先:否则找 "Control Center" 项 → 点它
        └─ 轮询 Control Center 的下拉窗口(最多 2 s)
             └─ 在窗口里找描述含 "wifi / wlan / 无线局域网" 的磁贴 → 点它
                  → 系统 Wi-Fi 菜单展开
```

实现要点:

1. **名称归一化**:去掉所有非字母数字并小写,这样 `Wi-Fi`、`Wi‐Fi`(U+2010 连字符)、`WiFi`、`无线局域网` 都能匹配;元素同时看 `AXRole` 和 `AXDescription`(macOS 把标题放在哪个属性并不固定)。
2. **不做任何坐标硬编码**:位置一律从 `AXPosition`/`AXSize` 现算,菜单栏重排、换显示器都不受影响。
3. **按名字找 Control Center,按"非时钟 + 尺寸合理"兜底**,避免未来改名后失灵。
4. **阻塞**:全程 `usleep` 等菜单动画,最长约 2 s,因此**必须在主线程之外调用**。
5. **不还原指针**:点击后指针停在目标上。刻意为之——移开可能让刚展开的子菜单收回去。

---

## 五、如何接入 NetBar

已接好一条最小、可回退的入口:**在状态项上 Option(⌥)单击 = 打开系统 Wi-Fi 菜单**;普通单击仍然是 NetBar 自己的面板。

见 [MenuBarPanel.swift](../../NetBar/App/MenuBarPanel.swift) 的 `togglePanel()` 与 `openSystemWiFiMenu()`。

想换触发方式,只改一处即可:

- 改成**普通单击直接调系统菜单**(彻底放弃自绘面板):把 `togglePanel()` 开头那段 `if NSEvent.modifierFlags.contains(.option)` 去掉。
- 改成**面板底部增加一行**(与 "Wi-Fi Settings..." 并列):在 [MenuRowViews.swift](../../NetBar/App/MenuRowViews.swift) 的 footer 里加一个 `SettingsLinkRow(title: "打开系统 Wi-Fi 菜单") { ... }`。
- 改成**第二个独立状态项**:在 `MenuBarController.start()` 里再建一个 `NSStatusItem`,action 直接调 `openSystemWiFiMenu()`。

失败路径已经处理好:

| 结果 | 处理 |
| --- | --- |
| `.notPermitted` | 弹系统授权提示 + 打开"系统设置 → 隐私与安全性 → 辅助功能" |
| `.noMenuBarItem` / `.noWiFiControl` | 退回到打开"Wi-Fi 设置"面板,不会静默失败 |

---

## 六、局限与风险

- **必须授权辅助功能**。首次使用会弹窗;用户拒绝则功能不可用(这是 TCC 设计,不是实现缺陷)。
- **会移动鼠标指针**,且菜单出现后需要用户自己点击或按 Esc 才消失。
- **本地化**:匹配用的是描述文本的归一化结果,已覆盖中英文常见写法;若系统语言更冷门,可能走不到第二条路径,此时返回 `.noWiFiControl` 并回退到设置面板。
- **不涉及私有 API / SIP / 公证问题**:全部使用公开的 Accessibility 与 CoreGraphics 事件接口,可正常签名与上架。
- **macOS 版本差异**:`AXExtrasMenuBar` 的宿主进程在历史版本里是 `SystemUIServer` → `ControlCenter` → `MenuBarAgent`,代码已按此顺序兼容。

---

## 七、复现命令

探针源码在 [probes/](probes/);编译与运行:

```sh
# 1. 看菜单栏真实结构(AX 命中测试)
clang -framework AppKit -framework ApplicationServices -o /tmp/scan probes/scan.m && /tmp/scan

# 2. 验证"AX 动作是空操作":对 Control Center 项执行 AXShowMenu,
#    前后对比 CGWindowList,窗口数不变
clang -framework AppKit -framework ApplicationServices -o /tmp/opentest2 probes/opentest2.m
/tmp/opentest2 'Control Center' AXShowMenu

# 3. 验证本方案:点击后系统 Wi-Fi 菜单出现
clang -fobjc-arc -I ../../NetBar/Bridge -framework AppKit -framework ApplicationServices \
      -o /tmp/verify probes/verify.m ../../NetBar/Bridge/NBSystemWiFiMenu.m && /tmp/verify
# outcome=0
# after: Known Networks=1 Other Networks=1 Personal Hotspot=2 Settings=1
# SYSTEM WIFI MENU IS OPEN
```

---

## 八、本次验证记录

| 项目 | 结果 |
| --- | --- |
| 桥接单独编译(`clang -fobjc-arc`) | 通过 |
| 端到端调用 `NBSystemWiFiMenu.openSystemWiFiMenu` | `outcome=0`(Opened),耗时 0.58 s |
| AX 复核系统 Wi-Fi 菜单内容 | Known Networks / Other Networks / Personal Hotspot / Wi‑Fi Settings… 全部出现 |
| Swift 侧调用(`NSEvent`、`Task.detached`、枚举分支)类型检查 | 通过 |
| 完整 Xcode 构建 `./Scripts/build.sh --debug` | **BUILD SUCCEEDED**,`NBSystemWiFiMenu` 已链接进 `NetBar.debug.dylib` |
| 单元测试 `./Scripts/build.sh --debug --test` | 全部通过 |

> 注:本机在受限文件沙箱下 `swift-plugin-server` 无法工作,会让 `xcodebuild` 在**未修改的**文件
> (`WiFiStore.swift` 的 `@Observable`、`MenuRowViews.swift` 的 `@State`)上报宏展开失败。
> 放开文件访问后构建与测试均正常——这是环境限制,与本次改动无关。

---

## 九、这个功能需要"辅助功能"权限

第一次使用(⌥ 单击状态项)会看到系统弹窗。授权路径:

**系统设置 → 隐私与安全性 → 辅助功能 → 勾选 NetBar**

未授权时 NetBar 会主动弹出该提示并跳到对应设置页。
