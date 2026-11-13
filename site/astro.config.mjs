import { defineConfig } from 'astro/config';

// Static output: the build writes plain files to ./dist, which Cloudflare
// Workers serves as static assets (see wrangler.toml).
//
// SITE_URL is the public origin of the site, e.g. https://example.com. It is
// only used to make the link preview image URL absolute (see Base.astro).
// Without it the build still works and the image URL stays root-relative.
export default defineConfig({
  output: 'static',
  site: process.env.SITE_URL || undefined,
});
