import AppKit
import Foundation
import SwiftUI

@main
final class AppMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments

        if args.contains("--dump") {
            let s = collectOnce()
            let payload: [String: Any] = [
                "onAC": s.onAC,
                "adapterW": s.adapterW,
                "adapterRatedW": s.adapterRatedW,
                "batteryW": s.batteryW,
                "soc": s.soc,
                "systemW": s.systemW,
                "cpuW": s.cpuW,
                "gpuW": s.gpuW,
                "cpuUtil": s.cpuUtil,
                "gpuUtil": s.gpuUtil,
                "cpuMeasured": s.cpuMeasured,
                "otherW": s.otherW,
                "usb": s.usb.map { ["name": $0.name, "watts": $0.watts] }
            ]
            let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            print(String(data: data, encoding: .utf8)!)
            exit(0)
        }

        if let idx = args.firstIndex(of: "--status-icon") {
            let path = args.indices.contains(idx + 1) ? args[idx + 1] : "/tmp/pf-status-icon.png"
            let s = collectOnce()
            let icon = AppDelegate.batteryIcon(soc: s.soc, charging: s.onAC && s.batteryW > 0.05, onAC: s.onAC)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 250, pixelsHigh: 120,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            icon.draw(in: CGRect(x: 0, y: 0, width: 250, height: 120))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
            try? png.write(to: URL(fileURLWithPath: path))
            print("status icon saved: \(path)")
            exit(0)
        }

        if args.contains("--pm-status") {
            let payload: [String: Any] = [
                "alive": PmHelperManager.helperAlive(),
                "script": PmHelperManager.scriptSource() ?? "missing"
            ]
            let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            print(String(data: data, encoding: .utf8)!)
            exit(0)
        }

        if args.contains("--pm-stop") {
            FileManager.default.createFile(atPath: PmHelperManager.stopPath, contents: Data())
            print("stop flag written: \(PmHelperManager.stopPath)")
            exit(0)
        }

        if args.contains("--pm-uninstall") {
            let pm = PmHelperManager()
            pm.uninstall()
            let deadline = Date().addingTimeInterval(180)
            while pm.state == .authorizing, Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
            }
            print("state: \(pm.state), note: \(pm.statusNote ?? "none")")
            exit(0)
        }

        if args.contains("--pm-start") {
            let pm = PmHelperManager()
            pm.enable()
            let deadline = Date().addingTimeInterval(180)
            while pm.state == .authorizing, Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
            }
            print("state: \(pm.state), note: \(pm.statusNote ?? "none")")
            exit(pm.state == .on ? 0 : 1)
        }

        if let idx = args.firstIndex(of: "--snapshot") {
            let path = args.indices.contains(idx + 1) ? args[idx + 1] : "/tmp/powerflow.png"
            let store = PowerStore()
            let s = collectOnce()
            store.prev = s
            store.target = s
            store.animStart = .distantPast
            let scheme: ColorScheme? = ProcessInfo.processInfo.environment["PF_SCHEME"] == "light" ? .light
                : (ProcessInfo.processInfo.environment["PF_SCHEME"] == "dark" ? .dark : nil)
            guard let image = SnapshotRenderer.render(store: store, scheme: scheme),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write("snapshot render failed\n".data(using: .utf8)!)
                exit(1)
            }
            try? png.write(to: URL(fileURLWithPath: path))
            print("snapshot saved: \(path)")
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    @MainActor
    static func collectOnce() -> PowerSample {
        if let s = PowerStore.syntheticSample() { return s }
        _ = CpuCollector.utilization()
        Thread.sleep(forTimeInterval: 0.6)
        let store = PowerStore()
        return store.buildSample()
    }
}
