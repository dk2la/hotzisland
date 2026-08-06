import Foundation
import IOKit.ps
import Observation

/// Watches power source changes: keeps observable battery state for module
/// views and emits a charging event whenever the Mac is plugged in/unplugged.
@MainActor
@Observable
final class PowerSourceMonitor {
    private(set) var percent: Int = 0
    private(set) var isPlugged: Bool = false

    @ObservationIgnored var onEvent: ((LiveEvent) -> Void)?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var wasOnAC: Bool?

    init() {
        PowerSourceMonitorRegistry.shared = self

        // IOKit takes a plain C function pointer, so the callback reaches the
        // instance through the MainActor registry.
        let callback: IOPowerSourceCallbackType = { _ in
            MainActor.assumeIsolated {
                PowerSourceMonitorRegistry.shared?.powerSourcesDidChange()
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        if let (onAC, percent) = currentPowerState() {
            wasOnAC = onAC
            isPlugged = onAC
            self.percent = percent
        }
    }

    private func powerSourcesDidChange() {
        guard let (onAC, percent) = currentPowerState() else { return }
        isPlugged = onAC
        self.percent = percent
        if let was = wasOnAC, was != onAC {
            onEvent?(.charging(percent: percent, plugged: onAC))
        }
        wasOnAC = onAC
    }

    private func currentPowerState() -> (onAC: Bool, percent: Int)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                let state = description[kIOPSPowerSourceStateKey] as? String,
                let percent = description[kIOPSCurrentCapacityKey] as? Int
            else { continue }
            return (state == kIOPSACPowerValue, percent)
        }
        return nil
    }
}

/// Bridge between the C callback and the MainActor monitor instance.
@MainActor
enum PowerSourceMonitorRegistry {
    static weak var shared: PowerSourceMonitor?
}
