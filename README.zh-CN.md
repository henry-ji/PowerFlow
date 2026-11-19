# Power Flow

模仿 AlDente Pro「Power Flow」的 macOS 菜单栏功耗流量图应用。菜单栏仅显示电池图标：填充比例 = SoC，充电时叠加闪电标记，用电池且低于 20% 时琥珀色填充（每 2 秒刷新）；悬停图标可在提示中看到 SoC、充电状态与带符号电池功率。点击图标弹出实时 Sankey 流量图：供电从哪来（电源适配器 / 电池）、系统总功耗、以及分流到 CPU、GPU、外接 USB 设备与其他组件的去向。流量带宽度与瓦数成正比。弹窗背景与配色跟随系统深浅色模式自动切换。

> English documentation: [README.md](README.md)

## 快速开始

```bash
./run.sh          # 构建并驻留菜单栏（点击闪电图标查看）
./make-app.sh     # 或打包为 dist/PowerFlow.app，可拷入 /Applications
./make-dmg.sh     # 生成可分发镜像 dist/PowerFlow.dmg（含拖拽安装快捷方式）
```

- 菜单栏常驻：仅电池图标（填充 = SoC、闪电 = 充电中、琥珀 = 低电），深浅色外观自适应；带符号电池功率见悬停提示与弹窗
- 左键点击菜单栏图标：打开 / 关闭流量图弹窗
- 右键点击菜单栏图标：保存快照 PNG、卸载实测守护进程、退出
- 每 2 秒采样一次，弹窗内数值与流量带平滑过渡动画；弹窗整体跟随系统深浅色模式
- CPU/GPU 始终采用内置 powermetrics 守护进程实测（首次启动一次管理员授权自动安装，见下节）

## 流量图结构

```
[电源适配器 | 电池]  →  [MacBook 系统枢纽]  →  CPU / GPU / 各 USB 设备 / Other
        └─(充电时)→  [电池]
```

- 接电源时：适配器输入功率分流为「系统负载」+「电池充电」
- 用电池时：电池放电流向系统枢纽，再分流到各组件
- 适配器功率不足（系统负载 > 适配器输入，如 30W 充电器带重负载）：适配器与电池作为**双源节点**同时向枢纽供电，电池流量带承担缺口，摘要条 Battery 显示琥珀色负值
- 顶部摘要条：Power Adapter / MacBook / Battery(±) / CPU / GPU / USB 一览
- 底部图例：各消费组件瓦数与 SoC、CPU、GPU 利用率

## 示例

适配器与电池同时向系统供电——30W 适配器带重负载，电池补足 8.5W 缺口（浅色模式；弹窗跟随系统外观自动切换）：

![双源供电：适配器与电池流量带同时汇入 MacBook 枢纽，再分流至 CPU、GPU、USB 与 Other](docs/assist-light.png)

## 数据源（Apple Silicon，免 sudo 主体）

| 数据 | 来源 | 性质 |
| --- | --- | --- |
| 适配器输入功率、电池充/放功率、系统负载 | `IOKit` AppleSmartBattery `PowerTelemetryData`（SystemPowerIn / BatteryPower / SystemLoad） | 实测 |
| SoC、充电状态、适配器标称瓦数 | `IOKit` AppleSmartBattery | 实测 |
| GPU 利用率 | `IOKit` IOAccelerator `PerformanceStatistics` | 实测 |
| CPU 利用率 | `host_processor_info` | 实测 |
| CPU / GPU 功耗 | 内置 powermetrics 守护进程实测（自动安装、一次授权）；仅无新鲜实测数据时回退利用率估算 | 实测 / 回退 |
| USB 设备功耗 | `IOKit` IOUSBHostDevice `UsbPowerSinkAllocation`（端口供电分配 mA）× 5V | 估算 |

守恒关系：适配器输入 ≈ 系统负载 + 充电功率；系统负载 = CPU + GPU + USB + Other（估算值会按系统负载实测值归一化，保证流量图闭合）。

## 实测 CPU/GPU（内置 powermetrics 守护进程）

`powermetrics` 需要 root 权限。应用把 `scripts/pm-helper.sh` 集成为自动管理的系统守护进程，**无界面开关、始终实测**：

1. 启动时若守护进程未在运行，弹出**一次** macOS 管理员授权框；
2. 授权后脚本安装到 `/Library/Application Support/PowerFlow/pm-helper.sh`（root 所有），
   并注册为 LaunchDaemon `/Library/LaunchDaemons/local.powerflow.pmhelper.plist`，由 launchd 持有、开机自启、崩溃自动拉起；
3. 守护进程每 2 秒采样一次，写入 `/tmp/powerflow-pm.json`（原始输出 `/tmp/pm-raw.txt`），应用读到新鲜数据即显示 MEASURED 徽章；
4. 若授权被取消或数据过期，回退为利用率估算（徽章 LIVE），下次启动自动重试安装；
5. 卸载：右键菜单「卸载实测守护进程…」或 `--pm-uninstall`（一次授权），移除 plist、脚本与标记。
   暂停/恢复采样无需密码：`--pm-stop` / `--pm-start`。

仍可选传统方式手动运行：`sudo ./scripts/pm-helper.sh`（同一脚本，支持停止标记）。

## CLI

```bash
.build/release/PowerFlowApp --dump                 # 打印一次采样 JSON
.build/release/PowerFlowApp --snapshot out.png     # 离屏渲染当前流量图 PNG
PF_SYNTHETIC=ac ... --snapshot out.png             # 合成数据（接电+充电+USB）布局预览
.build/release/PowerFlowApp --pm-status            # 守护进程存活 / 脚本路径
.build/release/PowerFlowApp --pm-start             # 未安装时安装并恢复采样（未安装需一次授权）
.build/release/PowerFlowApp --pm-stop              # 暂停采样（无需授权）
.build/release/PowerFlowApp --pm-uninstall         # 卸载守护进程（需一次授权）
```

## 项目结构

```
Sources/PowerFlowApp/
  AppMain.swift            入口（--dump / --snapshot / 菜单栏应用）
  AppDelegate.swift        状态栏图标、popover、右键菜单、快照
  Collectors/              电池遥测、CPU/GPU 利用率、USB、采样与估算
  Collectors/PmHelperManager.swift  实测守护进程安装/暂停/卸载（LaunchDaemon + 一次授权）
  Model/PowerSample.swift  采样模型与插值
  Views/                   摘要条、Sankey 流量图、弹窗布局
scripts/pm-helper.sh       powermetrics 实测守护进程（应用自动安装，亦可 sudo 手动）
run.sh / make-app.sh       启动 / 打包
```

## 分发与签名

`./make-dmg.sh` 产出 `dist/PowerFlow.dmg`：打开后把 Power Flow 拖入 Applications 即安装。
签名按优先级自动选择：Developer ID Application → Apple Development → ad-hoc。

- 本机只有 Apple Development 证书时，镜像可在本机与开发设备正常使用；
  **其他 Mac 首次打开会被 Gatekeeper 拦截**（无 Developer ID + 公证）：
  系统设置 → 隐私与安全性 → 「仍要打开」，或终端执行 `xattr -cr /Applications/Power\ Flow.app`。
- 面向公众分发需 Developer ID Application 证书签名并公证：
  `codesign --force --options runtime --timestamp --sign "Developer ID Application: …" dist/PowerFlow.app`
  后 `xcrun notarytool submit dist/PowerFlow.dmg --apple-id … --team-id … --password … --wait`
  并 `xcrun stapler staple dist/PowerFlow.dmg`。

## 说明

- 仅支持 Apple Silicon（功耗遥测依赖其 PMU 寄存器暴露的 PowerTelemetryData）。
- USB 功耗按端口供电分配（mA × 5V）估算，随充电状态变化；未接设备时 USB 显示 0.0 W。
- 无外接显示器/设备时，对应节点自动隐藏。
- 外接显示器耗电：独立供电的桌面显示器不消耗 Mac 的电能（仅视频信号），不属于流量图、也无法从 Mac 侧测量；由 Mac USB-C 供电的便携屏会枚举为 USB PD 受电设备，出现在 USB 分支（端口供电分配估算）。驱动外接显示器会抬高 GPU/WindowServer 功耗，计入 CPU/GPU 实测值，但无法单独拆出「显示器」一项。