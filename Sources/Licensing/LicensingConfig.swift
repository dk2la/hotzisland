import Foundation

/// Where licensing talks to, and whether it is enforced. None of these are
/// secrets. The three values are placeholders until the owner deploys the
/// Trial server (`worker/README.md`) and sets up the store.
enum LicensingConfig {
    /// Base URL of the Trial server (the Cloudflare Worker in `worker/`).
    static var trialServerURL: URL? {
        #if DEBUG
        // `--trial-server <url>`: point a debug build at a local Worker.
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--trial-server"), index + 1 < args.count {
            return URL(string: args[index + 1])
        }
        #endif
        return URL(string: "https://pocket-trial.example.workers.dev")
    }

    /// The store's product ID for Pocket; keys sold for anything else are
    /// rejected. With the placeholder `0` every key is rejected.
    static let productID = 0
    /// Checkout page the Buy button opens.
    static let checkoutURL = URL(string: "https://pocket.lemonsqueezy.com")

    /// Release builds always enforce licensing. Debug builds skip it, so
    /// daily work and demo recordings are not blocked; `--licensing` turns
    /// it on for testing the real flow.
    static var isEnforced: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--licensing")
        #else
        true
        #endif
    }
}
