import Foundation

/// Pre-render surgery on email HTML: drops what must never render. Pure
/// Foundation — no AppKit, no Theme — so the logic-only test target can
/// compile it without dragging the whole app in.
enum EmailHTMLSanitizer {
    /// Removes scripts, style sheets and the head block — their CSS fights
    /// the reader's restyle with competing !important rules. Images stay in
    /// the DOM: the web view hides them with CSS and blocks their network
    /// loads, so the show-images button can reveal them on demand.
    static func strip(_ html: String) -> String {
        var cleaned = html
        for pattern in [
            "<script[\\s\\S]*?</script>",
            "<style[\\s\\S]*?</style>",
            "<head[\\s\\S]*?</head>",
        ] {
            cleaned = cleaned.replacingOccurrences(
                of: pattern, with: "", options: [.regularExpression, .caseInsensitive]
            )
        }
        return cleaned
    }
}
