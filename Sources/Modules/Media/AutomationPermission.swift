import CoreServices
import Foundation

/// Checks Apple Events (Automation) permission towards a target app without
/// triggering the consent dialog — the dialog appears naturally on the first
/// real AppleScript call.
enum AutomationPermission {
    enum Status {
        case granted
        case denied
        /// Not asked yet, target not running, or the check failed.
        case undetermined
    }

    static func status(towardsBundleID bundleID: String) -> Status {
        var address = AEAddressDesc()
        guard let data = bundleID.data(using: .utf8) else { return .undetermined }
        let createStatus = data.withUnsafeBytes { bytes in
            AECreateDesc(typeApplicationBundleID, bytes.baseAddress, data.count, &address)
        }
        guard createStatus == noErr else { return .undetermined }
        defer { AEDisposeDesc(&address) }

        switch AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, false) {
        case noErr:
            return .granted
        case -1743: // errAEEventNotPermitted — the user declined automation
            return .denied
        default:
            return .undetermined
        }
    }
}
