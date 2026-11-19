import Foundation
import Combine

/// Optional privileged helper (scripts/pm-helper.sh) writes measured CPU/GPU milliwatts here.
private let pmHelperPath = "/tmp/powerflow-pm.json"

final class PowerStore: ObservableObject {
    @Published var prev = PowerSample()
    @Published var target = PowerSample()
    @Published var animStart = Date.distantPast

    let animDuration: TimeInterval = 1.1
    var onChange: ((PowerSample) -> Void)?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "powerflow.collect", qos: .userInitiated)

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
    }

    func sample(at date: Date) -> PowerSample {
        let t = min(max(date.timeIntervalSince(animStart) / animDuration, 0), 1)
        let eased = t * t * (3 - 2 * t)
        return PowerSample.lerp(prev, target, eased)
    }

    private func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let sample = ProcessInfo.processInfo.environment["PF_SYNTHETIC"] == "ac" ? PowerSample.demo : self.buildSample()
            // PMU telemetry reads zero for a few seconds around plug/unplug events; keep last good sample.
            guard sample.systemW > 0.05 else { return }
            DispatchQueue.main.async { self.publish(sample) }
        }
    }

    private func publish(_ sample: PowerSample) {
        prev = self.sample(at: Date())
        target = sample
        animStart = Date()
        onChange?(sample)
    }

    func buildSample() -> PowerSample {
        var s = PowerSample()
        guard let bat = BatteryCollector.read() else { return s }
        s.onAC = bat.onAC
        s.adapterRatedW = bat.adapterRatedW
        s.adapterW = bat.adapterInputW
        s.batteryW = bat.batteryW
        s.soc = bat.soc
        s.systemW = bat.systemLoadW
        s.cpuUtil = CpuCollector.utilization()
        s.gpuUtil = GpuCollector.utilization()
        s.usb = UsbCollector.devices()

        if let pm = Self.powermetricsReading() {
            s.cpuW = pm.cpu
            s.gpuW = pm.gpu
            s.cpuMeasured = true
        } else {
            // Estimate silicon power from utilization; scaled below to keep the diagram conservative.
            s.cpuW = 0.6 + 16.0 * pow(s.cpuUtil, 1.6)
            s.gpuW = 0.3 + 14.0 * pow(s.gpuUtil / 100.0, 1.6)
        }

        let usbW = s.usbW
        var budget = s.systemW - 0.2
        if budget < 0 { budget = 0 }
        let wanted = s.cpuW + s.gpuW + usbW
        if wanted > budget, wanted > 0 {
            let k = budget / wanted
            s.cpuW *= k; s.gpuW *= k
            s.usb = s.usb.map { UsbDevice(name: $0.name, watts: $0.watts * k) }
        }
        s.otherW = max(s.systemW - s.cpuW - s.gpuW - s.usbW, 0.2)
        return s
    }

    private static func powermetricsReading() -> (cpu: Double, gpu: Double)? {
        let url = URL(fileURLWithPath: pmHelperPath)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: pmHelperPath),
              let mtime = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mtime) < 6,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let cpu = (json["cpu_mw"] as? NSNumber)?.doubleValue ?? 0
        let gpu = (json["gpu_mw"] as? NSNumber)?.doubleValue ?? 0
        guard cpu + gpu > 0.001 else { return nil }
        return (cpu / 1000.0, gpu / 1000.0)
    }
}
