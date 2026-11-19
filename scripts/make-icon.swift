import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/powerflow-icon.png"
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a
    ])!
}

let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S), cornerWidth: 232, cornerHeight: 232, transform: nil)
ctx.addPath(bg)
ctx.clip()
let bgGrad = CGGradient(colorsSpace: cs, colors: [color(0x14171C), color(0x05070A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: S), options: [])

func ribbon(_ sy0: CGFloat, _ sy1: CGFloat, _ ty0: CGFloat, _ ty1: CGFloat, _ c0: UInt32, _ c1: UInt32) {
    let sx: CGFloat = 250, tx: CGFloat = 830, mx = (sx + tx) / 2
    let p = CGMutablePath()
    p.move(to: CGPoint(x: sx, y: sy0))
    p.addCurve(to: CGPoint(x: tx, y: ty0), control1: CGPoint(x: mx, y: sy0), control2: CGPoint(x: mx, y: ty0))
    p.addLine(to: CGPoint(x: tx, y: ty1))
    p.addCurve(to: CGPoint(x: sx, y: sy1), control1: CGPoint(x: mx, y: ty1), control2: CGPoint(x: mx, y: sy1))
    p.closeSubpath()
    ctx.saveGState()
    ctx.addPath(p)
    ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [color(c0), color(c1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: sx, y: 0), end: CGPoint(x: tx, y: 0), options: [])
    ctx.restoreGState()
}

ribbon(330, 400, 190, 260, 0xA8934A, 0x63B267)
ribbon(400, 620, 330, 550, 0xA8934A, 0x5D87C9)
ribbon(620, 760, 620, 760, 0x5D87C9, 0x8D7BD6)

func pill(_ rect: CGRect) {
    let p = CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil)
    ctx.addPath(p)
    ctx.setFillColor(color(0xFFFFFF, 0.10))
    ctx.fillPath()
    ctx.addPath(p)
    ctx.setStrokeColor(color(0xFFFFFF, 0.16))
    ctx.setLineWidth(3)
    ctx.strokePath()
}
pill(CGRect(x: 140, y: 330, width: 110, height: 430))
pill(CGRect(x: 830, y: 190, width: 110, height: 70))
pill(CGRect(x: 830, y: 330, width: 110, height: 220))
pill(CGRect(x: 830, y: 620, width: 110, height: 140))

let bolt = CGMutablePath()
let bx: CGFloat = 152, by: CGFloat = 440, bw: CGFloat = 86, bh: CGFloat = 200
bolt.move(to: CGPoint(x: bx + bw * 0.62, y: by))
bolt.addLine(to: CGPoint(x: bx, y: by + bh * 0.56))
bolt.addLine(to: CGPoint(x: bx + bw * 0.42, y: by + bh * 0.56))
bolt.addLine(to: CGPoint(x: bx + bw * 0.34, y: by + bh))
bolt.addLine(to: CGPoint(x: bx + bw, y: by + bh * 0.40))
bolt.addLine(to: CGPoint(x: bx + bw * 0.55, y: by + bh * 0.40))
bolt.closeSubpath()
ctx.addPath(bolt)
ctx.setFillColor(color(0xE6C05B))
ctx.fillPath()

guard let cg = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: cg)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: outPath))
print("icon: \(outPath)")
