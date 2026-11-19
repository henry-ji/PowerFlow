import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: PowerStore
    @ObservedObject var pm: PmHelperManager

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
            let sample = store.sample(at: context.date)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("Power Flow").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    Text(sample.cpuMeasured ? "MEASURED" : "LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient(colors: [Palette.mac, Palette.usb], startPoint: .leading, endPoint: .trailing)))
                        .foregroundStyle(.white)
                    if pm.state == .authorizing {
                        ProgressView().controlSize(.mini)
                    }
                    Button(action: { pm.setEnabled(pm.state == .off) }) {
                        HStack(spacing: 6) {
                            Text("实测").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                            Capsule()
                                .fill(pm.state != .off ? Palette.usb : Color.white.opacity(0.14))
                                .frame(width: 26, height: 14)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                                .overlay(
                                    Circle().fill(.white)
                                        .frame(width: 10, height: 10)
                                        .offset(x: pm.state != .off ? 6 : -6)
                                )
                                .animation(.easeInOut(duration: 0.18), value: pm.state)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(pm.state == .authorizing)
                    .opacity(pm.state == .authorizing ? 0.55 : 1)
                    .help("通过内置 powermetrics 守护进程实测 CPU/GPU 功耗；首次开启需一次管理员授权（安装为系统 LaunchDaemon），之后开关与开机自启均无需密码")
                    Spacer()
                    if sample.onAC, sample.adapterRatedW > 0 {
                        Text("Adapter \(sample.adapterRatedW) W").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                SummaryBar(sample: sample)
                SankeyView(store: store)
                    .frame(height: 290)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
                legend(sample)
                footnote
            }
            .padding(14)
            .frame(width: 780, height: 480)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.shell))
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
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
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 4)
    }

    private func legendItem(_ tint: Color, _ name: String, _ watts: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(name).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            Text(wattsText(watts) + " W").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.target.cpuMeasured {
                Text("CPU/GPU 由内置 powermetrics 守护进程实测（每 2 秒采样）。USB 功耗按端口供电分配（5V）估算。")
            } else {
                Text("CPU/GPU 为基于利用率的估算值；开启右上「实测」切换为 powermetrics 实测（首次需一次管理员授权安装守护进程，之后后台自动运行、开机自启）。USB 功耗按端口供电分配（5V）估算。")
            }
            if let note = pm.statusNote {
                Text(note).foregroundStyle(Palette.batteryOut.opacity(0.9))
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.white.opacity(0.35))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
