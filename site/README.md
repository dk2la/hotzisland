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
- `src/styles/global.css` — design tokens as CSS custom properties (palette,
  the two font stacks, spacing, layout, easings), plus the shared pieces:
  `.container`, `.section`, `.indent`, the type classes (`.h`, `.lede`,
  `.body`, `.label`), `.marker`, `.btn` and `.prose` for the legal pages. Use
  the tokens instead of raw values. The design rules:
  - Dark only (`color-scheme: dark`); there is no light theme.
  - Everything sits on a 64px grid (`--u`). The ground carries the grid as a
    tiled image, `src/assets/grid.svg`. The content column is 1088px
    (17 units) and text starts one unit (`--indent`) right of the section
    marker.
  - Square corners everywhere except the widget screenshots.
  - The accent green is only for Buy buttons and the price band.
  - Copy is typed in lowercase in the markup, never with `text-transform`, so
    the glossary terms Trial, License and License key keep their capitals.
  - Breakpoints: below 1152px the column is fluid, below 900px the first
    screen stacks, below 700px is the phone layout.
  - Only `transform` and `opacity` animate, and every animation is switched
    off or reduced to a fade under `prefers-reduced-motion`.
- Fonts — Geist and Geist Mono (OFL), self-hosted from the
  `@fontsource-variable/*` packages and imported in `Base.astro`. The site
  must not load anything from another origin: the Privacy page says so.
- `src/pages/` — one file per page. `index.astro` is the landing page;
  `404.astro` is served for unknown paths.
- `src/components/` — `Marker` (the 64px box with a letter that opens every
  section; down the landing page the letters spell P, O, C, K, E, and T in
  the footer; the legal pages and the 404 use P) and the landing page
  sections in order: `Hero` (first screen with the selected widget on a
  picture), `Figures` (the three figures and the laptop picture), `Sky`,
  `Price`, `Faq`.
- `src/scripts/` — plain TypeScript, no framework: `hero-demo.ts` (the loop
  that drags, resizes and docks the hero widget, and dragging it by hand) and
  `motion.ts` (everything that plays once when scrolled into view). Both
  honour `prefers-reduced-motion`, and the page is complete without them.
- `src/assets/pictures/` — the three halftone pictures. `src/assets/screens/` —
  copies of `docs/screenshots/*.png`; update the copies when the screenshots
  change. Astro resizes all of them to AVIF and WebP at build time. The
  screenshots are laid over the pictures as separate images so they can move
  on their own.
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
