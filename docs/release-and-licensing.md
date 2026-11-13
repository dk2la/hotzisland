# Release and licensing plan

Decisions agreed on 2026-11-10 for shipping Pocket to production and selling
License keys. Terms (License, License key, Trial, Activation, Subscription,
Subscription feature) are defined in [GLOSSARY.md](../GLOSSARY.md).

## Distribution

- Sold directly as a DMG plus a License key. Not on the Mac App Store, because
  window resizing needs the Accessibility API, which the App Store sandbox
  doesn't allow.
- Source code becomes proprietary and the repository private. The owner does
  this, including replacing the MIT `LICENSE`.
- Signing and notarization need an Apple Developer account, which doesn't exist
  yet. Until then, do the work that doesn't need one (hardened runtime,
  licensing, site).

## Downloads

- DMGs are hosted in a public Cloudflare R2 bucket, so downloads stay reachable
  after the repository goes private. The release workflow uploads to it on
  every release, before it creates the GitHub release.
- Stable URL, always the latest DMG (for the website's Download button):
  `https://pub-3c8757d8d4b64f55bbc715c162c7e969.r2.dev/Pocket.dmg`
- Each version keeps its own files under `v<version>/`:
  `Pocket-<version>.dmg`, `Pocket-<version>.zip` and `SHA256SUMS.txt`, e.g.
  `https://pub-3c8757d8d4b64f55bbc715c162c7e969.r2.dev/v0.1.2/Pocket-0.1.2.dmg`
- The bucket name and public base URL live in the repository variables
  `CLOUDFLARE_R2_BUCKET` and `CLOUDFLARE_R2_PUBLIC_URL`. The `r2.dev` address
  is Cloudflare's development URL; move the bucket to a custom domain once the
  website domain is chosen.

## Sales

- Store: **Lemon Squeezy** as merchant of record. It handles VAT, chargebacks
  and refunds and issues License keys with an Activation limit. The seller is
  an individual (French tax resident). Confirm eligibility and payouts when
  signing up.
- Price: **$24** one-time, **$19** launch price.
- Refunds: within 14 days of purchase, only if the License key was never
  activated. After activation the sale is final. A Refund Policy page is linked
  from the site footer, and the same rule is set in the store settings.

## License

- A License is permanent and includes every future feature that isn't a
  Subscription feature.
- Subscription features (e.g. future voice/AI control of the Mac) come later
  as a separate recurring Subscription. The first release has no Subscription.
- One License key, one person, up to **3 Activations** (Macs).

## Trial

- **3 days** with every feature available, starting at first launch.
- To make resetting the trial hard, a small Cloudflare Worker stores a hashed
  Mac ID with the trial start date, and Keychain keeps a local copy. Starting
  the trial needs an internet connection.
- When the trial ends without a License, Pocket locks completely and shows
  only the buy / enter-key screen. There is no limited free mode.

## License checks

- Activation is online, through the Lemon Squeezy license API.
- Pocket re-validates the key **once a day**.
- Without a network, Pocket keeps working for up to **7 days** after the last
  successful check, then asks to reconnect.

## Updates

- Auto-updates via Sparkle.

## Website

- Hosted on Cloudflare Workers (static assets), on its own domain (not chosen
  yet).
- Pages: landing with Buy and Download, Terms, Privacy, Refund Policy.
- Design: custom, with animations, in the style of the current widget. The
  design isn't discussed yet; a mockup comes later.
- Privacy policy: states what the network audit (issue #58) found. Our server
  stores only a hashed Mac ID and the trial start date; Lemon Squeezy gets the
  License key and the hashed Mac ID. Mail and the Assistant talk to the user's
  own providers, and Gravatar, Spotify and Apple dictation are disclosed.
  Re-run the audit whenever a feature adds a network request (e.g. Sparkle).

## Open questions

- Where the Sparkle feed is hosted. It must stay reachable after the main
  repository goes private. (DMGs are settled, see Downloads.)
- Website domain.
- Website design (mockup first).
