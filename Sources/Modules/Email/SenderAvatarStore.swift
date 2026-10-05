import AppKit
import CryptoKit
import Foundation
import Observation
import OSLog

/// Sender pictures for the inbox, Gmail-style: a Gravatar for the address
/// when one exists, otherwise the caller falls back to coloured initials.
/// Results (including "none") are cached in memory and on disk, so each
/// address is looked up once per install rather than once per row render.
@MainActor
@Observable
final class SenderAvatarStore {
    /// Loaded pictures by lowercased address. Views read this; a missing
    /// key means "not looked up yet", `nil` means "looked up, none".
    private(set) var images: [String: NSImage?] = [:]

    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "avatars")
    @ObservationIgnored private let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("com.dk2la.hotzisland/avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Pixel size requested from Gravatar — rows draw at 32pt, so 2x.
    nonisolated private static let requestedSize = 80

    /// The picture for `address`, kicking off a lookup the first time an
    /// address is seen. Returns nil until it lands (or when there is none).
    func image(for address: String) -> NSImage? {
        let key = Self.normalized(address)
        guard !key.isEmpty else { return nil }
        if let cached = images[key] {
            return cached
        }
        lookup(key)
        return nil
    }

    private func lookup(_ key: String) {
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let hash = Self.hash(key)
        let file = cacheDirectory.appendingPathComponent(hash)
        let missing = cacheDirectory.appendingPathComponent(hash + ".none")
        Task { [weak self] in
            let result = await Self.load(hash: hash, file: file, missingMarker: missing)
            guard let self else { return }
            self.images[key] = result
            self.inFlight.remove(key)
        }
    }

    /// Disk cache first, then Gravatar with `d=404` so unknown addresses
    /// come back empty instead of as a generated placeholder.
    nonisolated private static func load(hash: String, file: URL, missingMarker: URL) async -> NSImage? {
        if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            return image
        }
        if FileManager.default.fileExists(atPath: missingMarker.path) {
            return nil
        }
        guard let url = URL(string: "https://www.gravatar.com/avatar/\(hash)?s=\(requestedSize)&d=404") else {
            return nil
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse
        else { return nil } // Offline: no marker, so the next launch retries.
        if http.statusCode == 200, let image = NSImage(data: data) {
            try? data.write(to: file, options: .atomic)
            return image
        }
        if http.statusCode == 404 {
            FileManager.default.createFile(atPath: missingMarker.path, contents: nil)
        }
        return nil
    }

    private static func normalized(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Gravatar keys on the MD5 of the lowercased, trimmed address.
    nonisolated private static func hash(_ key: String) -> String {
        Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
