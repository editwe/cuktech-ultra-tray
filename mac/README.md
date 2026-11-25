# CUKTECH 10 Ultra · macOS 菜单栏功率表

macOS 版的「酷态科 10 号 Ultra」功率表：一个菜单栏小工具，蓝牙直连充电器，
状态栏上直接显示四口总功率，点开看四路电压/电流/功率和充电模式，还能直接断电。

纯 Swift 写的（AppKit + SwiftUI + CoreBluetooth），不需要 Electron、不需要装运行时。
目标系统 macOS 13 或更新（Apple Silicon 与 Intel 都行）。

---

## 和 Windows 版的关系

同一套协议、同一套取色规则、同样的数字格式，两边都是从一个充电器上读出来的：

| | Windows 版 | macOS 版 |
|---|---|---|
| 语言 / 技术 | C# + NativeAOT，自绘 Win32 界面 | Swift + AppKit/SwiftUI |
| 常驻位置 | 托盘图标 + 任务栏数字 | 状态栏（menu bar）文字 |
| 找设备 | 按 MAC 直连（Windows 缓存里有） | 扫 FE95 广播反解 MAC 再连 |
| 配置 | settings.json | ~/Library/Application Support/CuktechTray/config.json |
| 配对 | 扫码登录小米云 → 取 token | 一样（向导四屏） |
| 体积 | 约 10.4 MB 单文件 exe | 约 1 MB 的 .app |

两者的配置可以互相抄：Windows 版 settings.json 里的 `Mac` 与 `TokenHex` 就是 macOS 版 config.json 里的 `mac` 与 `tokenHex`。

---

## 安装

下载 `CuktechTray-<版本>-mac.zip`，解压出 `CuktechTray.app`，拖进「应用程序」。

> macOS 版的版本号**自己算**，从 `0.1.0` 起，不跟 Windows 版的 0.4.x 绑在一起——两个平台改动节奏不一样，
> 绑同一个号只会让更新日志里一半条目跟对方无关。当前版本见 `--version`。

这个 .app 是 **ad-hoc 签名**（本仓库没有 Apple 开发者账号，没做公证），第一次打开时
macOS 会拦一下：

1. 右键点 `CuktechTray.app` → 打开，或者双击后在弹窗里点「取消」；
2. 进 **系统设置 → 隐私与安全性**，往下滚到「安全性」，点「仍要打开」；
3. 再双击一次就开了。

如果是从命令行解压的，也可以直接去掉隔离属性：

```bash
xattr -dr com.apple.quarantine /Applications/CuktechTray.app
```

第一次启动会问蓝牙权限，必须给，否则状态栏只会显示 `—`。点掉那个弹窗之前程序会一直等
（最多 30 秒，之后再进入重试退避），所以「先看到 `—`、允许之后才出数字」是正常的。

> 每次重新构建、重新签名（ad-hoc 签名每次都会变）之后，系统会再问一次蓝牙权限，
> 因为 macOS 把 App 当成新的二进制看待。用官方 zip 的用户只会在第一次见到这个弹窗。

---

## 第一次用：扫一次码

菜单栏出现 `未配对` 时会自动弹向导，四屏长这样（这是 CI 在真 macOS 上截的）：

![配对向导四屏：认路 / 扫码 / 挑设备 / 完成](../docs/mac-wizard.png)


1. **认路** —— 说明为什么要扫码：充电器的 token 只在你自己小米账号的设备清单里；这一屏底部还有一段隐私说明（点「看完整的隐私说明」看全文）；
2. **扫码** —— 用「米家」App 扫码登录（只读设备清单，token 存在本机）；
3. **挑设备** —— 列表里带「酷态科」的排最前，选这台 10 号 Ultra；
4. **完成** —— 状态栏立刻开始显示功率。

如果云端没给蓝牙地址（有些账号的 `mac` 字段是空的），向导会顺手扫一遍附近的
FE95 广播，用广播里反解出来的地址补上。实在不行还有「手动填 MAC 和 token」的兜底，
从 Windows 版的 settings.json 抄两个值就行。

---

## 日常

- 菜单栏上那串数字就是四口总功率，颜色按档走：灰 ≈0W、淡蓝 0–20W、绿 20–60W、黄 60–100W、红 100W 以上；
- **左键点一下**数字：弹出面板（四路读数、每路的开关、四种充电模式）；
- 面板默认**点外面就收起**（点到别的 App、桌面都算）；想让它常驻就点右上角的**图钉**，
  钉住之后切 App 也不收，再点一次取消；
- **右键**：弹菜单 —— 显示功率面板 / 重新连接 / 重新配对… / 菜单栏显示功率数字 / 打开日志 / 显示配置文件 / 关于 / 退出；
- 关掉「菜单栏显示功率数字」后，菜单栏换成一个闪电图标（跟 App 图标上的那个对应），
  悬停能看到实时读数；不占地方，也不会有个「瓦」字在那儿晃；
- 「关于」里有版本号、GitHub 仓库入口和**更新检查**（打开时会自动查一次，
  比的是 release 里 `CuktechTray-<版本>-mac.zip` 这个资产名，不看 tag —— mac 版自己编号，跟 Windows 版的号不是一回事）；
- 面板里的开关是「读 → 改 → 写 → 回读确认」，写失败会回退，不会把别的口一起关掉；
- 断开或者走远了会自动重连，重连不上就先显示 `—`。

---

## 隐私

和 Windows 版完全一致：只碰**你自己账号里这台充电器的凭据**和**它自己的读数**。

- **扫码时**：向小米云要一个登录二维码，账号、密码、验证码全程在你手机上，本程序看不见也拿不到；
  配对完成时小米云只返回这台充电器的 `mac` 与 12 字节 `tokenHex`
- **凭据在哪**：只写本机的 `~/Library/Application Support/CuktechTray/config.json`（登录会话另存 `session.json`，
  只为「重新配对」时少扫一次码；删掉不影响日常使用）
- **日常**：跟充电器蓝牙直连读功率、写四路开关，全程不联网；只有你打开「关于」（会顺手查一次版本）
  或点「检查更新」才会访问一次 GitHub Releases —— 拿的是公开的发布列表，不带任何账号信息
- **不做的事**：不上传读数、不做统计、不装后台服务、不碰账号里的其它设备；卸载后本机不留东西

向导欢迎页那段小字点开就是上面这些。

---
## 命令行参数

```bash
/Applications/CuktechTray.app/Contents/MacOS/CuktechTray --version     # 打印版本号
/Applications/CuktechTray.app/Contents/MacOS/CuktechTray --selftest    # 自检：配置路径、是否已配对
/Applications/CuktechTray.app/Contents/MacOS/CuktechTray --wizard-demo=<屏>  # 只摆出向导某一屏（welcome|login|pick|done），截图用
```

---

## 自己编译

需要 Xcode 命令行工具（或者完整 Xcode）：

```bash
# 在 Intel 或 Apple Silicon 的任意一台 Mac 上都能出 universal（arm64 + x86_64）：
bash mac/scripts/build-universal.sh mac            # 编出 mac/.build/release/CuktechTray（fat）
bash mac/scripts/make-app.sh mac/.build/release/CuktechTray dist   # 组装 .app + ad-hoc 签名
bash mac/scripts/package.sh dist                   # 打成 dist/CuktechTray-<版本>-mac.zip
dist/CuktechTray.app/Contents/MacOS/CuktechTray --selftest
open dist/CuktechTray.app
```

只想编本机架构的话直接 `swift build -c release --package-path mac` 也行。

`make-app.sh` 会顺手跑 `scripts/make-icon.swift` 现画一套 `AppIcon.iconset`，再用 `iconutil`
打成 `AppIcon.icns` 塞进 `Contents/Resources`。图标是**构建时生成**的，仓库里不放 `.icns`：
二进制进 git 没法 review，改配色就得重新导出一堆 PNG。想换图标只改那个脚本里的两个颜色常量。
（`build-universal.sh` 存在的理由：GitHub 的 arm64 runner 排队经常被取消，所以 CI 固定用
Intel runner 编两个架构——SwiftPM 多 `--arch` 的产物落在 `.build/apple/Products/Release/`，
脚本负责把它挪回 `.build/release/`。）

跑测试：

```bash
swift test --package-path mac
```

协议那部分（AES-CCM、HKDF、MiOT 编解码、小米云客户端）跟界面完全解耦，
在 Linux 上也能跑，所以 CI 里有一条 ubuntu job 专门跑单元测试。

---

## 目录

```
mac/
  Package.swift                SwiftPM 清单（CuktechCore / CuktechBle / CuktechTray）
  Sources/CuktechCore/         协议核心：AES-CCM、HKDF、MiOT 编解码、小米云客户端
  Sources/CuktechBle/          CoreBluetooth：连接、认证、扫描
  Sources/CuktechTray/         菜单栏 App：状态栏、面板（含固定）、向导、关于/更新检查
  Tests/CuktechCoreTests/      单元测试（黄金向量、协议、云端解析）
  Tests/CuktechBleTests/       广播解析回归测试（只在 macOS 上编译）
  scripts/build-universal.sh   在单台机器上编 universal（arm64 + x86_64）
  scripts/make-app.sh          组装 .app、生成图标并签名
  scripts/make-icon.swift      画 AppIcon.iconset（构建时调用）
  scripts/package.sh           打成 CuktechTray-<版本>-mac.zip
  Resources/Info.plist         包信息（LSUIElement、蓝牙权限说明）
```

---

## 出问题了看这里

日志在 `~/Library/Application Support/CuktechTray/tray.log`（右键菜单「打开日志」），
认证每一步、每次重连、每次写入口都记在里面。

| 现象 | 原因 / 处理 |
|---|---|
| 状态栏一直是 `—`，日志里反复出现 `扫不到 MAC 为 … 的广播` | 0.1.0 的已知 bug，已在当前代码里修掉：MiBeacon 广播解析把 `95 FE` 服务 UUID 头当成必需的，但 macOS 通过 `CBAdvertisementDataServiceDataKey` 给的是**裸 payload**（`10 59 0E 66 00 30 8B 31 73 CD 3C`），于是永远解析失败。更新到修复后的版本即可；自己编译的话 `swift test` 里有一条用真机字节写的回归测试 |
| 日志 `蓝牙 30 秒内没就绪` | 授权弹窗没点，或「系统设置 → 隐私与安全性 → 蓝牙」里没勾上本程序 |
| `central state=4` / 一直重启扫描 | 蓝牙关着（state 4 是 poweredOff），打开蓝牙 |
| 连上但读数是 0，日志 `四个端口都没有应答` | 手机上的米家正连着这台充电器。BLE 同时只允许一个中心，把米家退到后台或关掉手机蓝牙 |
| `认证结果` 不是 0x21，或 HMAC 校验失败 | token 不对/已过期：设备被解绑或换绑过。右键「重新配对…」重扫一次 |
| 面板开关点了弹回原状 | 写入口失败（设备忙或有负载）。读-改-写带回读校验，失败会回退并写日志 |
| 重新编译后菜单栏不见了 | ad-hoc 签名每次构建都会变，系统重新要一次蓝牙权限；允许后即可 |

## 已知限制

- **没做公证**：只有 ad-hoc 签名，第一次打开要走「隐私与安全性 → 仍要打开」。想彻底顺畅得买 Apple 开发者账号（99 美元/年）做 Developer ID 签名 + 公证。
- **蓝牙这块没有真机回归**：GitHub 的 macOS runner 是没有蓝牙硬件的虚拟机，CI 只能验证「编译过、单测全绿、界面能起来」，连充电器那一步必须自己机器上跑。
- **只在自己机器上验过**：开发过程中没有第二台 Mac，Intel 与 Apple Silicon 都是 CI 编出来的，实际连设备以你手上的为准。
- 菜单栏宽度是 `NSStatusItem.variableLength`，刘海屏机器上建议别把字号调太大。

---

## 许可证

[MIT](../LICENSE)。与小米、酷态科官方没有任何关系，是照公开资料和协议实测自己写的第三方小工具。
