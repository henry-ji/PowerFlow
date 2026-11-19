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
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Power Flow")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Power Flow — 电池充/放功率（+ 充电 / − 放电）"
        }
        updateStatusTitle(PowerSample())
        store.onChange = { [weak self] sample in self?.updateStatusTitle(sample) }
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

    private func updateStatusTitle(_ s: PowerSample) {
        let w = s.batteryW
        let sign = w > 0.05 ? "+" : (w < -0.05 ? "−" : "")
        let text = " " + sign + wattsText(abs(w)) + "W"
        let tint: NSColor = w > 0.05 ? .pfCharge : (w < -0.05 ? .pfDischarge : .secondaryLabelColor)
        statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: tint
        ])
        if ProcessInfo.processInfo.environment["PF_TITLE_LOG"] == "1" {
            FileHandle.standardError.write("title:\(text)\n".data(using: .utf8)!)
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
    static func render(store: PowerStore, size: CGSize = CGSize(width: 780, height: 480)) -> NSImage? {
        let view = PopoverView(store: store).frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.nsImage
    }
}
