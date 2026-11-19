import Foundation

struct UsbDevice: Equatable {
    var name: String
    var watts: Double
}

struct PowerSample: Equatable {
    var ts: Date = Date()
    var onAC: Bool = true
    var adapterW: Double = 0          // measured wall input
    var adapterRatedW: Int = 0
    var batteryW: Double = 0          // + charging, - discharging
    var soc: Double = 0               // 0...100
    var systemW: Double = 0           // measured system load
    var cpuW: Double = 0
    var gpuW: Double = 0
    var cpuUtil: Double = 0           // 0...1
    var gpuUtil: Double = 0           // 0...100
    var cpuMeasured: Bool = false     // true when powermetrics helper is live
    var usb: [UsbDevice] = []
    var otherW: Double = 0

    var usbW: Double { usb.reduce(0) { $0 + $1.watts } }
    var batteryAbsW: Double { abs(batteryW) }
    var sourceW: Double { onAC ? adapterW : batteryAbsW }

    static let demo = PowerSample(
        ts: Date(),
        onAC: true,
        adapterW: 57.1,
        adapterRatedW: 60,
        batteryW: 45.0,
        soc: 71,
        systemW: 12.1,
        cpuW: 3.4,
        gpuW: 2.2,
        cpuUtil: 0.22,
        gpuUtil: 18,
        cpuMeasured: false,
        usb: [UsbDevice(name: "USB-C Hub", watts: 2.5), UsbDevice(name: "Keyboard", watts: 0.5)],
        otherW: 3.5
    )

    static func lerp(_ a: PowerSample, _ b: PowerSample, _ t: Double) -> PowerSample {
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var usbNames: [String] = []
        for d in a.usb where !usbNames.contains(d.name) { usbNames.append(d.name) }
        for d in b.usb where !usbNames.contains(d.name) { usbNames.append(d.name) }
        let usb = usbNames.map { name -> UsbDevice in
            let wa = a.usb.first { $0.name == name }?.watts ?? 0
            let wb = b.usb.first { $0.name == name }?.watts ?? 0
            return UsbDevice(name: name, watts: m(wa, wb))
        }.filter { $0.watts > 0.02 }
        return PowerSample(
            ts: b.ts,
            onAC: t < 0.5 ? a.onAC : b.onAC,
            adapterW: m(a.adapterW, b.adapterW),
            adapterRatedW: b.adapterRatedW,
            batteryW: m(a.batteryW, b.batteryW),
            soc: m(a.soc, b.soc),
            systemW: m(a.systemW, b.systemW),
            cpuW: m(a.cpuW, b.cpuW),
            gpuW: m(a.gpuW, b.gpuW),
            cpuUtil: m(a.cpuUtil, b.cpuUtil),
            gpuUtil: m(a.gpuUtil, b.gpuUtil),
            cpuMeasured: b.cpuMeasured,
            usb: usb,
            otherW: m(a.otherW, b.otherW)
        )
    }
}
