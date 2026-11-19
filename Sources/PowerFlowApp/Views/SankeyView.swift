import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0)
    }
}

enum Palette {
    static let adapter = Color(hex: 0xE6C05B)
    static let battery = Color(hex: 0x63B267)
    static let batteryOut = Color(hex: 0xE0A04A)
    static let mac = Color(hex: 0x6AA4E4)
    static let cpu = Color(hex: 0x8D7BD6)
    static let gpu = Color(hex: 0xB06FD8)
    static let usb = Color(hex: 0x46B3A4)
    static let other = Color(hex: 0x9AA0A6)
    static let streamIn = Color(hex: 0xA8934A)
    static let streamMid = Color(hex: 0x5D87C9)
    static let card = Color(white: 0.16)
    static let shell = Color(white: 0.05)
}

func symbolName(_ candidates: [String]) -> String {
    for name in candidates where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return name }
    return candidates.last ?? "circle.fill"
}

func wattsText(_ w: Double) -> String {
    if w >= 99.95 { return String(format: "%.0f", w) }
    return String(format: "%.1f", w)
}

struct SankeyNode: Identifiable {
    let id: String
    let rect: CGRect
    let symbol: String
    let tint: Color
    let watts: Double
    let showWatts: Bool
}

struct SankeyRibbon: Identifiable {
    let id: String
    let path: Path
    let from: Color
    let to: Color
    let opacity: Double
    let label: String?
    let labelPoint: CGPoint
}

struct SankeyLayout {
    var nodes: [SankeyNode] = []
    var ribbons: [SankeyRibbon] = []
}

func sankeyLayout(_ s: PowerSample, size: CGSize) -> SankeyLayout {
    var out = SankeyLayout()
    let nodeW: CGFloat = 46
    let H = size.height
    guard H > 60, size.width > 300 else { return out }

    struct Consumer { let id: String; let w: Double; let tint: Color; let symbol: String }
    var consumers: [Consumer] = [
        Consumer(id: "cpu", w: s.cpuW, tint: Palette.cpu, symbol: symbolName(["cpu"])),
        Consumer(id: "gpu", w: s.gpuW, tint: Palette.gpu, symbol: symbolName(["gpu", "cpu.fill", "memorychip"]))
    ]
    for d in s.usb where d.watts > 0.05 {
        consumers.append(Consumer(id: "usb:" + d.name, w: d.watts, tint: Palette.usb, symbol: symbolName(["usb", "cable.connector", "bolt.horizontal.fill"])))
    }
    consumers.append(Consumer(id: "other", w: s.otherW, tint: Palette.other, symbol: "ellipsis"))

    let charge = max(s.batteryW, 0)
    let discharge = max(-s.batteryW, 0)
    let system = s.systemW
    let col0Total = s.onAC ? s.adapterW : discharge
    let col1Total = system + charge

    let gap1: CGFloat = consumers.count > 1 ? 10 : 0
    let gap0: CGFloat = charge > 0.05 ? 16 : 0
    let col2Nodes = consumers.count
    let gap2: CGFloat = CGFloat(max(col2Nodes - 1, 0)) * 10

    var scale = CGFloat.greatestFiniteMagnitude
    if col0Total > 0.05 { scale = min(scale, H / CGFloat(col0Total)) }
    if col1Total > 0.05 { scale = min(scale, (H - gap0) / CGFloat(col1Total)) }
    if system > 0.05 { scale = min(scale, (H - gap2) / CGFloat(system)) }
    if scale == .greatestFiniteMagnitude || scale <= 0 { scale = 1 }

    func th(_ w: Double) -> CGFloat { w > 0.02 ? max(CGFloat(w) * scale, 3) : 0 }

    let x0: CGFloat = 4
    let x1 = size.width * 0.47 - nodeW / 2
    let x2 = size.width - nodeW - 4

    // column 0
    let srcStack = (charge > 0.05 ? th(charge) : 0) + th(system)
    let col0H = max(th(col0Total), srcStack)
    let col0Y = (H - col0H) / 2
    let srcRect = CGRect(x: x0, y: col0Y, width: nodeW, height: max(col0H, 46))
    if s.onAC {
        out.nodes.append(SankeyNode(id: "adapter", rect: srcRect, symbol: symbolName(["powerplug.fill", "powerplug"]), tint: Palette.adapter, watts: s.adapterW, showWatts: true))
    } else {
        out.nodes.append(SankeyNode(id: "batterysrc", rect: srcRect, symbol: symbolName(["battery.75", "battery.50"]), tint: Palette.batteryOut, watts: discharge, showWatts: true))
    }

    // column 1
    let battH = th(charge)
    let macH = max(th(system), consumers.reduce(0) { $0 + th($1.w) } + gap2)
    let col1H = (charge > 0.05 ? max(battH, 30) + gap0 : 0) + max(macH, 46)
    var y1 = (H - col1H) / 2
    var battRect = CGRect.zero
    if charge > 0.05 {
        battRect = CGRect(x: x1, y: y1, width: nodeW, height: max(battH, 30))
        out.nodes.append(SankeyNode(id: "battery", rect: battRect, symbol: symbolName(["battery.100.bolt", "battery.75"]), tint: Palette.battery, watts: charge, showWatts: false))
        y1 += battRect.height + gap0
    }
    let macRect = CGRect(x: x1, y: y1, width: nodeW, height: max(macH, 46))
    out.nodes.append(SankeyNode(id: "mac", rect: macRect, symbol: symbolName(["laptopcomputer"]), tint: Palette.mac, watts: system, showWatts: false))

    // column 2
    let col2H = consumers.reduce(0) { $0 + max(th($1.w), 30) } + gap2
    var y2 = (H - col2H) / 2
    var consumerRects: [String: CGRect] = [:]
    for c in consumers {
        let r = CGRect(x: x2, y: y2, width: nodeW, height: max(th(c.w), 30))
        consumerRects[c.id] = r
        out.nodes.append(SankeyNode(id: c.id, rect: r, symbol: c.symbol, tint: c.tint, watts: c.w, showWatts: false))
        y2 += r.height + 10
    }

    func ribbon(id: String, sx: CGFloat, sy0: CGFloat, sy1: CGFloat, tx: CGFloat, ty0: CGFloat, ty1: CGFloat, from: Color, to: Color, opacity: Double, watts: Double) {
        var p = Path()
        let mx = (sx + tx) / 2
        p.move(to: CGPoint(x: sx, y: sy0))
        p.addCurve(to: CGPoint(x: tx, y: ty0), control1: CGPoint(x: mx, y: sy0), control2: CGPoint(x: mx, y: ty0))
        p.addLine(to: CGPoint(x: tx, y: ty1))
        p.addCurve(to: CGPoint(x: sx, y: sy1), control1: CGPoint(x: mx, y: ty1), control2: CGPoint(x: mx, y: sy1))
        p.closeSubpath()
        let thickness = min(sy1 - sy0, ty1 - ty0)
        let label = thickness >= 12 && (tx - sx) > 130 ? wattsText(watts) + " W" : nil
        let lp = CGPoint(x: (sx + tx) / 2, y: (sy0 + sy1 + ty0 + ty1) / 4)
        out.ribbons.append(SankeyRibbon(id: id, path: p, from: from, to: to, opacity: opacity, label: label, labelPoint: lp))
    }

    // source -> column 1
    let srcRight = srcRect.maxX
    if s.onAC {
        var sy = srcRect.minY + (srcRect.height - srcStack) / 2
        if charge > 0.05 {
            let t = th(charge)
            ribbon(id: "adp-bat", sx: srcRight, sy0: sy, sy1: sy + t, tx: battRect.minX, ty0: battRect.midY - t / 2, ty1: battRect.midY + t / 2, from: Palette.streamIn, to: Palette.battery, opacity: 0.9, watts: charge)
            sy += t
        }
        let t = th(system)
        ribbon(id: "adp-mac", sx: srcRight, sy0: sy, sy1: sy + t, tx: macRect.minX, ty0: macRect.minY, ty1: macRect.minY + t, from: Palette.streamIn, to: Palette.streamMid, opacity: 0.9, watts: system)
    } else {
        let t = th(system)
        ribbon(id: "bat-mac", sx: srcRight, sy0: srcRect.minY + (srcRect.height - t) / 2, sy1: srcRect.minY + (srcRect.height - t) / 2 + t, tx: macRect.minX, ty0: macRect.minY, ty1: macRect.minY + t, from: Palette.battery, to: Palette.streamMid, opacity: 0.9, watts: system)
    }

    // mac -> consumers
    var my = macRect.minY + (macRect.height - consumers.reduce(0) { $0 + th($1.w) }) / 2
    for c in consumers {
        let t = th(c.w)
        guard let r = consumerRects[c.id] else { continue }
        let to: Color = c.tint
        let fromC = Palette.streamMid
        let opacity: Double = c.id == "other" ? 0.5 : 0.85
        ribbon(id: "mac-" + c.id, sx: macRect.maxX, sy0: my, sy1: my + t, tx: r.minX, ty0: r.midY - t / 2, ty1: r.midY + t / 2, from: fromC, to: to, opacity: opacity, watts: c.w)
        my += t
    }
    return out
}

struct SankeyView: View {
    @ObservedObject var store: PowerStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let sample = store.sample(at: context.date)
            GeometryReader { geo in
                let layout = sankeyLayout(sample, size: geo.size)
                ZStack {
                    ForEach(layout.ribbons) { r in
                        r.path.fill(
                            LinearGradient(colors: [r.from, r.to], startPoint: .leading, endPoint: .trailing)
                                .opacity(r.opacity)
                        )
                    }
                    Canvas { ctx, _ in
                        let spacing: CGFloat = 110
                        let bandW: CGFloat = 30
                        let shift = CGFloat(context.date.timeIntervalSinceReferenceDate * 70)
                            .truncatingRemainder(dividingBy: spacing)
                        for r in layout.ribbons {
                            let b = r.path.boundingRect
                            var clipped = ctx
                            clipped.clip(to: r.path)
                            var x = b.minX - spacing + shift
                            while x < b.maxX + spacing {
                                var band = Path()
                                band.move(to: CGPoint(x: x, y: b.minY - 4))
                                band.addLine(to: CGPoint(x: x + bandW, y: b.minY - 4))
                                band.addLine(to: CGPoint(x: x + bandW - 18, y: b.maxY + 4))
                                band.addLine(to: CGPoint(x: x - 18, y: b.maxY + 4))
                                band.closeSubpath()
                                clipped.fill(band, with: .color(.white.opacity(0.09 * r.opacity)))
                                x += spacing
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    ForEach(layout.ribbons) { r in
                        if let label = r.label {
                            Text(label)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                                .position(r.labelPoint)
                        }
                    }
                    ForEach(layout.nodes) { n in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            VStack(spacing: 4) {
                                Image(systemName: n.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(n.tint)
                                if n.showWatts && n.rect.height >= 64 {
                                    Text(wattsText(n.watts) + " W")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                        }
                        .frame(width: n.rect.width, height: n.rect.height)
                        .position(x: n.rect.midX, y: n.rect.midY)
                    }
                }
            }
        }
    }
}
