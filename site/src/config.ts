// The one place for the site's outbound links and prices. Every Buy button
// links to `checkoutURL`, every Download button to `downloadURL`.

/**
 * Lemon Squeezy checkout page.
 *
 * KEEP IN SYNC with `LicensingConfig.checkoutURL` in
 * `Sources/Licensing/LicensingConfig.swift`: the website and the app's Buy
 * button must open the same page. The value is a placeholder until the store
 * exists; change both files together.
 */
export const checkoutURL = 'https://pocket.lemonsqueezy.com';

/**
 * Stable URL of the latest DMG in the public Cloudflare R2 bucket.
 * See "Downloads" in `docs/release-and-licensing.md`.
 */
export const downloadURL = 'https://pub-3c8757d8d4b64f55bbc715c162c7e969.r2.dev/Pocket.dmg';

/** One-time prices as shown on the page. The store charges the real amount. */
export const price = {
  /** Launch price, the one currently charged. */
  launch: '$19',
  /** Regular price after the launch period. */
  regular: '$24',
} as const;
