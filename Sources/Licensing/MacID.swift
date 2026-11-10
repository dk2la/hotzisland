import CryptoKit
import Foundation
import IOKit

/// This Mac's identity for licensing: the hardware UUID, hashed so the raw
/// identifier never leaves the Mac.
enum MacID {
    /// Hashed Mac ID of this machine: 64 lowercase hex characters.
    static var current: String {
        hashed(hardwareID: hardwareUUID() ?? "")
    }

    /// SHA-256 of the hardware identifier, salted with the app's name so the
    /// value is useless for matching against other apps' hashes.
    static func hashed(hardwareID: String) -> String {
        SHA256.hash(data: Data("com.dk2la.pocket:\(hardwareID)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// IOPlatformUUID — stable across reinstalls and OS updates.
    private static func hardwareUUID() -> String? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        let value = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String
    }
}
