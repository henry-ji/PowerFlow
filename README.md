# Power Flow

An AlDente Pro "Power Flow"-style macOS menu bar app that draws a live Sankey diagram of your Mac's power flow: where power comes from (power adapter / battery), total system load, and how it splits across CPU, GPU, attached USB devices and other components. Ribbon width is proportional to wattage.

The menu bar icon shows a bolt plus the current signed battery power: green `+45.0W` while charging, amber `−9.0W` while discharging, neutral `0.0W` when balanced (monospaced digits, refreshed every 2 s). Click it to open the live diagram popover.

> 中文文档：[README.zh-CN.md](README.zh-CN.md)

## Quick start

```bash
./run.sh          # build and stay in the menu bar (click the bolt icon)
./make-app.sh     # or package dist/PowerFlow.app, copy into /Applications
./make-dmg.sh     # distributable image dist/PowerFlow.dmg (drag-to-install shortcut)
```

- Menu bar resident: bolt icon + signed battery power (+ charge / − discharge), color follows charge state, adapts to light/dark appearance
- Left-click the menu bar icon: open / close the flow popover
- Right-click the menu bar icon: save a snapshot PNG, uninstall the measurement daemon, quit
- Samples every 2 s; popover values and ribbons transition smoothly, with a flowing-band animation
- CPU/GPU power is always measured by the built-in powermetrics daemon (one-time admin authorization on first launch, then automatic — see below)

## Diagram structure

```
[Power Adapter | Battery]  →  [MacBook system hub]  →  CPU / GPU / each USB device / Other
        └─(while charging)→  [Battery]
```

- On AC: adapter input splits into "system load" + "battery charging"
- On battery: discharge flows into the system hub, then splits to consumers
- Top summary bar: Power Adapter / MacBook / Battery(±) / CPU / GPU / USB at a glance
- Bottom legend: per-consumer wattage plus SoC, CPU and GPU utilization

## Data sources (Apple Silicon, sudo-free core)

| Data | Source | Nature |
| --- | --- | --- |
| Adapter input, battery charge/discharge, system load | `IOKit` AppleSmartBattery `PowerTelemetryData` (SystemPowerIn / BatteryPower / SystemLoad) | measured |
| SoC, charge state, adapter rated wattage | `IOKit` AppleSmartBattery | measured |
| GPU utilization | `IOKit` IOAccelerator `PerformanceStatistics` | measured |
| CPU utilization | `host_processor_info` | measured |
| CPU / GPU power | built-in powermetrics daemon (auto-installed, one-time admin auth); utilization-based estimate only as fallback when no fresh measurement exists | measured / fallback |
| USB device power | `IOKit` IOUSBHostDevice `UsbPowerSinkAllocation` (port power allocation mA) × 5 V | estimated |

Conservation: adapter input ≈ system load + charging power; system load = CPU + GPU + USB + Other (estimates are normalized against the measured system load so the diagram always closes).

## Measured CPU/GPU (built-in powermetrics daemon)

`powermetrics` requires root. The app ships `scripts/pm-helper.sh` and manages it as a system daemon automatically — there is no UI toggle, measurement is always on:

1. On launch, if the daemon is not running, the app shows **one** macOS administrator authorization prompt;
2. After authorization the script is installed to `/Library/Application Support/PowerFlow/pm-helper.sh` (root-owned) and registered as the LaunchDaemon `/Library/LaunchDaemons/local.powerflow.pmhelper.plist`, owned by launchd, started at boot, relaunched on crash;
3. The daemon samples every 2 s into `/tmp/powerflow-pm.json` (raw output in `/tmp/pm-raw.txt`); fresh data switches the popover badge to MEASURED;
4. If authorization is declined or data is stale, the app falls back to utilization-based estimates (badge LIVE) and retries installation on next launch;
5. Uninstall: right-click menu "卸载实测守护进程…" or `--pm-uninstall` (one authorization) removes plist, script and stop flag. Pause/resume sampling without a password via `--pm-stop` / `--pm-start`.

The traditional manual route still works: `sudo ./scripts/pm-helper.sh` (same script, honors the stop flag).

## CLI

```bash
.build/release/PowerFlowApp --dump                 # print one sample as JSON
.build/release/PowerFlowApp --snapshot out.png     # offscreen-render the current diagram to PNG
PF_SYNTHETIC=ac ... --snapshot out.png             # synthetic sample (AC + charging + USB) layout preview
.build/release/PowerFlowApp --pm-status            # daemon alive / script path
.build/release/PowerFlowApp --pm-start             # install if needed and resume sampling (one auth if absent)
.build/release/PowerFlowApp --pm-stop              # pause sampling (no auth)
.build/release/PowerFlowApp --pm-uninstall         # uninstall the daemon (one auth)
```

## Project layout

```
Sources/PowerFlowApp/
  AppMain.swift            entry point (--dump / --snapshot / menu bar app)
  AppDelegate.swift        status item, popover, right-click menu, snapshots
  Collectors/              battery telemetry, CPU/GPU utilization, USB, sampling & estimation
  Collectors/PmHelperManager.swift  daemon install/pause/uninstall (LaunchDaemon + one-time auth)
  Model/PowerSample.swift  sample model and interpolation
  Views/                   summary bar, Sankey diagram, popover layout
scripts/pm-helper.sh       powermetrics measurement daemon (auto-installed; also sudo-runnable)
run.sh / make-app.sh       launch / package
```

## Distribution & signing

`./make-dmg.sh` produces `dist/PowerFlow.dmg`: open it and drag Power Flow into Applications.
Signing identity is picked by priority: Developer ID Application → Apple Development → ad-hoc.

- With only an Apple Development certificate the image works on this Mac and dev devices;
  **other Macs get a Gatekeeper prompt on first open** (no Developer ID + notarization):
  System Settings → Privacy & Security → "Open Anyway", or `xattr -cr /Applications/Power\ Flow.app`.
- For public distribution, sign with a Developer ID Application certificate and notarize:
  `codesign --force --options runtime --timestamp --sign "Developer ID Application: …" dist/PowerFlow.app`
  then `xcrun notarytool submit dist/PowerFlow.dmg --apple-id … --team-id … --password … --wait`
  and `xcrun stapler staple dist/PowerFlow.dmg`.

## Notes

- Apple Silicon only (power telemetry relies on PowerTelemetryData exposed by its PMU).
- USB power is estimated from port power allocation (mA × 5 V) and varies with charge state; with no device attached USB shows 0.0 W.
- Nodes for absent displays/devices hide automatically.