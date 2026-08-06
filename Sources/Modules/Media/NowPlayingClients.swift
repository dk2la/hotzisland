import AppKit

/// Enumerates every app that currently publishes media state to the system
/// (browsers, players, …) — the same set Control Center shows.
///
/// Only the *list* is read here. Per-client playback info is deliberately not
/// requested: `MRMediaRemoteGetNowPlayingInfoForClient` and its `ForApp`
/// sibling crash or hang when called from outside Apple's own clients, so
/// track data comes from the current now-playing item or AppleScript instead.
@MainActor
enum NowPlayingClients {
    private typealias GetClientsFn = @convention(c) (DispatchQueue, @escaping (CFArray?) -> Void) -> Void
    private typealias ClientBundleFn = @convention(c) (AnyObject) -> Unmanaged<CFString>?

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW
    )

    private static let getClients: GetClientsFn? = symbol("MRMediaRemoteGetNowPlayingClients")
    private static let getBundleID: ClientBundleFn? = symbol("MRNowPlayingClientGetBundleIdentifier")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    /// Bundle IDs of all current media clients, most recent first.
    static func bundleIDs() async -> [String] {
        guard let getClients, let getBundleID else { return [] }
        return await withCheckedContinuation { continuation in
            getClients(DispatchQueue.main) { array in
                let clients = (array as? [AnyObject]) ?? []
                let ids = clients.compactMap { client in
                    getBundleID(client)?.takeUnretainedValue() as String?
                }
                continuation.resume(returning: ids)
            }
        }
    }

    static func displayName(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        return bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }
}
