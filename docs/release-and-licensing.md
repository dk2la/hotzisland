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

- Hosted on Cloudflare Pages, on its own domain (not chosen yet).
- Pages: landing with Buy and Download, Terms, Privacy, Refund Policy.
- Design: custom, with animations, in the style of the current widget. The
  design isn't discussed yet; a mockup comes later.
- Privacy policy: email, calendar and notes stay on the Mac. Only a hashed Mac
  ID and the trial date reach our server, and Lemon Squeezy validates keys.
  Check the code before writing this, to confirm nothing else leaves the Mac.

## Open questions

- Where DMGs and the Sparkle feed are hosted: an S3 bucket or a public GitHub
  repository. It must stay reachable after the main repository goes private.
- Website domain.
- Website design (mockup first).
