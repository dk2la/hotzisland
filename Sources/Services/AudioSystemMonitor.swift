import CoreAudio
import AudioToolbox
import Foundation
import Observation

/// Watches the default audio output device and its volume. Keeps observable
/// state for module views, emits events on device/volume changes, and can
/// set the system volume.
@MainActor
@Observable
final class AudioSystemMonitor {
    private(set) var volume: Double = 0
    private(set) var currentDeviceName: String?

    @ObservationIgnored var onEvent: ((LiveEvent) -> Void)?

    @ObservationIgnored private var deviceID = AudioObjectID(kAudioObjectUnknown)
    /// The first device-change callback fires for the device present at
    /// launch — that one should not produce a visible event.
    @ObservationIgnored private var suppressInitialDeviceEvent = true

    @ObservationIgnored private var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    @ObservationIgnored private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    /// Stored so the exact same block can be detached from the previous
    /// device when the default output changes.
    @ObservationIgnored private let volumeListener: AudioObjectPropertyListenerBlock = { _, _ in
        MainActor.assumeIsolated {
            AudioSystemMonitorRegistry.shared?.volumeDidChange()
        }
    }
    @ObservationIgnored private let deviceListener: AudioObjectPropertyListenerBlock = { _, _ in
        MainActor.assumeIsolated {
            AudioSystemMonitorRegistry.shared?.defaultDeviceDidChange()
        }
    }

    init() {
        AudioSystemMonitorRegistry.shared = self
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            .main,
            deviceListener
        )
        defaultDeviceDidChange()
    }

    private func defaultDeviceDidChange() {
        var newID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress, 0, nil, &size, &newID
        ) == noErr, newID != AudioObjectID(kAudioObjectUnknown), newID != deviceID else { return }

        if deviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, .main, volumeListener)
        }
        deviceID = newID
        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, .main, volumeListener)
        currentDeviceName = deviceName(deviceID)
        refreshVolume()

        if suppressInitialDeviceEvent {
            suppressInitialDeviceEvent = false
        } else if let name = currentDeviceName {
            onEvent?(.audioDevice(name: name))
        }
    }

    private func volumeDidChange() {
        refreshVolume()
        onEvent?(.volume(level: volume))
    }

    private func refreshVolume() {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &level) == noErr
        else { return }
        volume = Double(level)
    }

    /// Sets the system output volume (0...1). The property listener fires
    /// afterwards and keeps `volume` in sync.
    func setVolume(_ level: Double) {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        var value = Float32(min(max(level, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, size, &value)
        if status == noErr {
            volume = Double(value)
        }
    }

    private func deviceName(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}

/// Bridge between non-isolated CoreAudio callbacks and the MainActor monitor.
@MainActor
enum AudioSystemMonitorRegistry {
    static weak var shared: AudioSystemMonitor?
}
