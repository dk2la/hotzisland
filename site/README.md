# Pocket website

The Pocket website: an [Astro](https://astro.build) project that builds to
static files and is served by Cloudflare Workers as static assets. There is no
Worker script. (`worker/` at the repository root is a different thing: the
Trial server.)

## Build

Requires Node 22 or newer. From this directory:

```sh
npm ci && npm run build
```

The site is written to `dist/`.

## Preview

```sh
npm run dev      # development server with live reload, http://localhost:4321
npm run preview  # serves the built dist/ as-is, http://localhost:4321
```

## Layout

- `src/config.ts` — the checkout URL, the download URL and the prices. Every
  Buy and Download button reads them from here. `checkoutURL` must stay equal
  to `LicensingConfig.checkoutURL` in `Sources/Licensing/LicensingConfig.swift`.
- `src/layouts/Base.astro` — the shared layout (head with link preview tags,
  header, footer). Every page wraps its content in it. Props: `title`
  (optional, rendered as "Title — Pocket") and `description` (optional meta
  description). A named `head` slot accepts extra `<head>` tags.
- `src/styles/global.css` — design tokens (colors, radii, spacing, motion) as
  CSS custom properties, plus the shared pieces: `.container`, `.btn`,
  `.mono`, `.prose` for the legal pages, scroll reveal. Dark appearance
  follows the system setting through `prefers-color-scheme`. Use the tokens
  instead of raw values. The phone layout is `@media (max-width: 760px)`.
- `src/pages/` — one file per page. `index.astro` is the landing page;
  `404.astro` is served for unknown paths.
- `src/components/` — the landing page sections: `Hero` (first screen),
  `WidgetStage` (the live widget demo inside it), `Screens`, `Price`, `Faq`.
- `src/scripts/` — plain TypeScript, no framework: `widget-demo.ts` (demo
  loop, dragging, docking, the panel) and `reveal.ts` (scroll reveal and the
  License meters). Both honour `prefers-reduced-motion`.
- `src/assets/screens/` — copies of `docs/screenshots/*.png`. Astro resizes
  them to WebP at build time; update the copies when the screenshots change.
- `public/` — files copied to the site root unchanged, including `og.png`,
  the link preview image.
- `scripts/og.html` — the source of `public/og.png`. Not part of the build;
  the command to regenerate the PNG is at the top of the file.

## Site URL

The site has no final domain yet. Set the `SITE_URL` environment variable at
build time to the public origin, without a trailing path:

```sh
SITE_URL=https://example.com npm run build
```

It is only used to make the link preview image URL (`og:image`,
`twitter:image`) absolute, which link previews require. Without it the build
still works and those tags point to `/og.png`, which most services will not
load. In CI the build step in `.github/workflows/site.yml` reads it from the
`SITE_URL` repository variable; set that variable once the address is known. There is no canonical link and no `og:url` yet; add
them together with the domain.

## Deploy

Deploys run from GitHub Actions, never from a local machine. The workflow
`.github/workflows/site.yml` runs on every push to `master` that changes
`site/**` (or the workflow itself), and can be started by hand from the Actions
tab. It runs on a GitHub-hosted runner, builds the site and runs
`wrangler deploy`, which uploads `dist/` to the Worker named `pocket-site`
(see `wrangler.toml`). The site is then available at
`https://pocket-site.<account-subdomain>.workers.dev`.

### Required repository secrets

| Secret | Value |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | A Cloudflare API token created from the "Edit Cloudflare Workers" template |
| `CLOUDFLARE_ACCOUNT_ID` | The ID of the Cloudflare account that owns the Worker |

Set them under Settings → Secrets and variables → Actions.
