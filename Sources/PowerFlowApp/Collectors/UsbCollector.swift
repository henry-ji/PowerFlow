import Foundation
import IOKit

enum UsbCollector {
    /// External USB devices with estimated bus power: port sink allocation (mA) @ 5 V.
    static func devices() -> [UsbDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [UsbDevice] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }

            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(service, &nameBuf)
            let fallbackName = String(cString: nameBuf)
            let name = (dict["kUSBProductString"] as? String)
                ?? (dict["USB Product Name"] as? String)
                ?? fallbackName

            let mA = ((dict["UsbPowerSinkAllocation"] as? NSNumber)
                ?? (dict["UsbPowerSinkCapability"] as? NSNumber))?.doubleValue ?? 0
            let watts = 5.0 * mA / 1000.0
            guard watts > 0.02 else { continue }
            if let i = result.firstIndex(where: { $0.name == name }) {
                result[i].watts += watts
            } else {
                result.append(UsbDevice(name: name, watts: watts))
            }
        }
        return result.sorted { $0.watts > $1.watts }
    }
}
