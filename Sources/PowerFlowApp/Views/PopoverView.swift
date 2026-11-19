import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: PowerStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
            let sample = store.sample(at: context.date)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("Power Flow").font(.system(size: 16, weight: .heavy)).foregroundStyle(Palette.text)
                    Text(sample.cpuMeasured ? "MEASURED" : "LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient(colors: [Palette.mac, Palette.usb], startPoint: .leading, endPoint: .trailing)))
                        .foregroundStyle(.white)
                    Spacer()
                    if sample.onAC, sample.adapterRatedW > 0 {
                        Text("Adapter \(sample.adapterRatedW) W").font(.system(size: 10)).foregroundStyle(Palette.textFaint)
                    }
                }
                SummaryBar(sample: sample)
                SankeyView(store: store)
                    .frame(height: 290)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
                legend(sample)
            }
            .padding(14)
            .frame(width: 780, height: 480)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.shell))
        }
    }

    @ViewBuilder
    private func legend(_ s: PowerSample) -> some View {
        HStack(spacing: 14) {
            legendItem(Palette.cpu, "CPU", s.cpuW)
            legendItem(Palette.gpu, "GPU", s.gpuW)
            ForEach(s.usb, id: \.name) { d in
                legendItem(Palette.usb, d.name, d.watts)
            }
            legendItem(Palette.other, "Other", s.otherW)
            Spacer()
            Text("SoC \(Int(s.soc.rounded()))% · CPU \(Int((s.cpuUtil * 100).rounded()))% · GPU \(Int(s.gpuUtil.rounded()))%")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textFaint)
        }
        .padding(.horizontal, 4)
    }

    private func legendItem(_ tint: Color, _ name: String, _ watts: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(name).font(.system(size: 10)).foregroundStyle(Palette.textSoft).lineLimit(1)
            Text(wattsText(watts) + " W").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.text)
        }
    }
}
