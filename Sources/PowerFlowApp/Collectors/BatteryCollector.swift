import Foundation
import IOKit

enum BatteryCollector {
    struct Reading {
        var onAC: Bool
        var adapterInputW: Double
        var adapterRatedW: Int
        var batteryW: Double     // signed: + charging
        var soc: Double
        var systemLoadW: Double
    }

    static func read() -> Reading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        let telemetry = dict["PowerTelemetryData"] as? [String: Any] ?? [:]
        func mw(_ key: String) -> Double {
            if let n = telemetry[key] as? NSNumber { return n.doubleValue / 1000.0 }
            return 0
        }
        let external = (dict["ExternalConnected"] as? Bool) ?? false
        let charging = (dict["IsCharging"] as? Bool) ?? false
        let adapterDetails = dict["AdapterDetails"] as? [String: Any]
        let rated = (adapterDetails?["Watts"] as? NSNumber)?.intValue ?? 0

        let current = (dict["CurrentCapacity"] as? NSNumber)?.doubleValue ?? 0
        let maxCap = (dict["MaxCapacity"] as? NSNumber)?.doubleValue ?? 100
        let soc = maxCap > 0 ? current / maxCap * 100.0 : 0

        let batteryMag = mw("BatteryPower")   // signed: + charging, - discharging
        let systemLoad = mw("SystemLoad")
        let inputMeasured = mw("SystemPowerIn")

        let batteryW = external && abs(batteryMag) < 0.05 ? 0 : batteryMag
        // SystemPowerIn refreshes only every ~30s; derive input from the instantaneous
        // conservation identity instead: input = system load + signed battery power.
        let system = systemLoad > 0.1 ? systemLoad : max(inputMeasured - max(batteryW, 0), 0)
        let input = external ? (systemLoad > 0.1 ? max(system + batteryW, 0) : inputMeasured) : 0

        return Reading(onAC: external,
                       adapterInputW: input,
                       adapterRatedW: rated,
                       batteryW: batteryW,
                       soc: soc,
                       systemLoadW: system)
    }
}
