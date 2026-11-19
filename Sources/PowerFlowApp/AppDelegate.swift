import AppKit
import SwiftUI

extension NSColor {
    static let pfCharge = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.39, green: 0.70, blue: 0.40, alpha: 1)
            : NSColor(srgbRed: 0.18, green: 0.49, blue: 0.20, alpha: 1)
    }
    static let pfDischarge = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.88, green: 0.63, blue: 0.29, alpha: 1)
            : NSColor(srgbRed: 0.63, green: 0.35, blue: 0.00, alpha: 1)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    let store = PowerStore()
    let pm = PmHelperManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Power Flow — 电池充/放功率（+ 充电 / − 放电）"
        }
        updateStatusItem(PowerSample())
        store.onChange = { [weak self] sample in self?.updateStatusItem(sample) }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 780, height: 480)
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
        store.start()
        pm.startMonitoring()
        pm.enable()
        if ProcessInfo.processInfo.environment["PF_AUTOSHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func updateStatusItem(_ s: PowerSample) {
        let w = s.batteryW
        let sign = w > 0.05 ? "+" : (w < -0.05 ? "−" : "")
        let charging = s.onAC && w > 0.05
        if let button = statusItem.button {
            button.image = Self.batteryIcon(soc: s.soc, charging: charging, onAC: s.onAC)
            button.image?.isTemplate = false
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Power Flow — SoC \(Int(s.soc.rounded()))% · " +
                (charging ? "充电中" : (s.onAC ? "接电源" : "用电池")) +
                " · " + sign + wattsText(abs(w)) + "W"
        }
    }

    static func batteryIcon(soc: Double, charging: Bool, onAC: Bool) -> NSImage {
        NSImage(size: NSSize(width: 25, height: 12), flipped: false) { _ in
            let body = CGRect(x: 0.5, y: 0.5, width: 21, height: 11)
            let nub = CGRect(x: 22.2, y: 3.5, width: 2.3, height: 5)
            let outline = NSColor.labelColor.withAlphaComponent(0.9)
            let shell = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
            shell.lineWidth = 1
            outline.setStroke()
            shell.stroke()
            outline.setFill()
            NSBezierPath(roundedRect: nub, xRadius: 1, yRadius: 1).fill()
            let frac = min(max(soc / 100, 0), 1)
            let inner = body.insetBy(dx: 2, dy: 2)
            if frac > 0.01 {
                let fillRect = CGRect(x: inner.minX, y: inner.minY,
                                      width: max(inner.width * frac, 1.5), height: inner.height)
                let fill: NSColor = charging ? .pfCharge
                    : (soc <= 20 && !onAC ? .pfDischarge : NSColor.labelColor.withAlphaComponent(0.85))
                fill.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 1.2, yRadius: 1.2).fill()
            }
            if charging {
                let cx = body.midX, cy = body.midY
                let bolt = NSBezierPath()
                bolt.move(to: CGPoint(x: cx + 1.7, y: cy + 3.6))
                bolt.line(to: CGPoint(x: cx - 2.3, y: cy + 0.4))
                bolt.line(to: CGPoint(x: cx - 0.3, y: cy + 0.4))
                bolt.line(to: CGPoint(x: cx - 1.7, y: cy - 3.6))
                bolt.line(to: CGPoint(x: cx + 2.3, y: cy - 0.4))
                bolt.line(to: CGPoint(x: cx + 0.3, y: cy - 0.4))
                bolt.close()
                NSColor.black.withAlphaComponent(0.65).setFill()
                bolt.fill()
                NSColor.white.withAlphaComponent(0.9).setStroke()
                bolt.lineWidth = 0.7
                bolt.stroke()
            }
            return true
        }
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Save Snapshot…", action: #selector(saveSnapshot), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "卸载实测守护进程…", action: #selector(uninstallHelper), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Power Flow", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        let location = NSPoint(x: 0, y: (statusItem.button?.bounds.height ?? 0) + 4)
        menu.popUp(positioning: nil, at: location, in: statusItem.button)
    }

    @objc private func saveSnapshot() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "powerflow.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let image = SnapshotRenderer.render(store: store),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    @objc private func uninstallHelper() {
        pm.uninstall()
    }

    @objc private func quit() {
        store.stop()
        pm.stopMonitoring()
        NSApp.terminate(nil)
    }
}

enum SnapshotRenderer {
    @MainActor
    static func render(store: PowerStore, scheme: ColorScheme? = nil, size: CGSize = CGSize(width: 780, height: 480)) -> NSImage? {
        var view = AnyView(PopoverView(store: store).frame(width: size.width, height: size.height))
        if let scheme {
            view = AnyView(view.environment(\.colorScheme, scheme))
        }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.nsImage
    }
}
