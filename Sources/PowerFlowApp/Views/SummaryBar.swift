import SwiftUI

struct Chip: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let label: String
    let value: String
    let valueTint: Color?
}

struct SummaryBar: View {
    let sample: PowerSample

    private var chips: [Chip] {
        var c: [Chip] = []
        if sample.onAC {
            c.append(Chip(id: "src", symbol: symbolName(["powerplug.fill", "powerplug"]), tint: Palette.adapter,
                          label: "Power Adapter", value: wattsText(sample.adapterW) + " W", valueTint: nil))
        } else {
            c.append(Chip(id: "src", symbol: symbolName(["battery.75", "battery.50"]), tint: Palette.batteryOut,
                          label: "Battery", value: wattsText(sample.batteryAbsW) + " W", valueTint: nil))
        }
        c.append(Chip(id: "mac", symbol: symbolName(["laptopcomputer"]), tint: Palette.mac,
                      label: "MacBook", value: wattsText(sample.systemW) + " W", valueTint: nil))
        if sample.onAC {
            let battTint: Color = sample.batteryW >= 0 ? Palette.battery : Palette.batteryOut
            let sign = sample.batteryW >= 0 ? "+" : "-"
            c.append(Chip(id: "bat", symbol: symbolName(["battery.100.bolt", "battery.75"]), tint: battTint,
                          label: "Battery", value: sign + wattsText(sample.batteryAbsW) + " W", valueTint: battTint))
        }
        c.append(Chip(id: "cpu", symbol: symbolName(["cpu"]), tint: Palette.cpu,
                      label: "CPU", value: wattsText(sample.cpuW) + " W", valueTint: nil))
        c.append(Chip(id: "gpu", symbol: symbolName(["gpu", "cpu.fill", "memorychip"]), tint: Palette.gpu,
                      label: "GPU", value: wattsText(sample.gpuW) + " W", valueTint: nil))
        c.append(Chip(id: "usb", symbol: symbolName(["usb", "cable.connector", "bolt.horizontal.fill"]), tint: Palette.usb,
                      label: "USB", value: wattsText(sample.usbW) + " W", valueTint: nil))
        return c
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { i, chip in
                if i > 0 {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 10)
                }
                HStack(spacing: 6) {
                    Image(systemName: chip.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(chip.tint)
                    Text(chip.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1).fixedSize()
                    Text(chip.value).font(.system(size: 11, weight: .bold)).foregroundStyle(chip.valueTint ?? .white).lineLimit(1).fixedSize()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}
