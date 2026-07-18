import { execSync } from "node:child_process";
import { defineConfig } from "vite";
import { VitePWA } from "vite-plugin-pwa";

// Build-time version info, baked into the bundle via `define` below and shown
// in the corner "about" badge. The git SHA lets a running PWA report exactly
// which deploy it is; the timestamp disambiguates rebuilds of the same commit.
// Both fall back gracefully when git isn't available (e.g. a tarball build).
function gitSha() {
  try {
    return execSync("git rev-parse --short HEAD").toString().trim();
  } catch {
    return "unknown";
  }
}
const buildVersion = gitSha();
const buildTime = new Date().toISOString();

// PR-preview builds ship a *self-destroying* service worker instead of the real
// PWA one. Previews are pruned and rebuilt on every push, so a normal precaching
// SW pins a stale app shell whose now-deleted hashed bundle 404s — and it
// survives a reload because the SW serves that shell from cache regardless of
// HTTP freshness (exactly the "bad <script src> until I clear storage" trap).
// `selfDestroying` emits a worker at the usual SW URL that unregisters itself
// and clears its caches, so it also cleans up any preview SW already installed
// on a reviewer's device. Prod builds (no SLEIGHT_PREVIEW) keep the full offline
// PWA. The pr-preview workflow sets SLEIGHT_PREVIEW=1 for its `mise run bundle`.
const isPreview = process.env.SLEIGHT_PREVIEW === "1";

// `base: "./"` makes emitted asset URLs relative, so the built site works when
// GitHub Pages serves it from a project subpath (https://<user>.github.io/<repo>/)
// rather than a domain root. Vite resolves the bare `core/…` specifier that the
// compiled ReScript emits via the workspace symlink and bundles the module graph.
//
// PWA note: everything installability-related is kept *relative* on purpose so
// it inherits the GitHub Pages subpath without hardcoding the repo name:
//   - `scope`/`start_url`/`id` are "./" and resolve against the manifest URL
//     (`/<repo>/manifest.webmanifest`), i.e. to `/<repo>/`.
//   - The service worker is emitted at the app root and registered from the
//     app (via `virtual:pwa-register`) with a relative URL, so its scope
//     defaults to `/<repo>/`.
//   - Icon `src`s are relative and resolve next to the manifest.
export default defineConfig({
  base: "./",
  // Expose the build version to the app as compile-time constants. Vite
  // string-replaces these identifiers; the ReScript entry reads them through
  // `@val external` bindings (see src/Main.res).
  define: {
    __APP_VERSION__: JSON.stringify(buildVersion),
    __BUILD_TIME__: JSON.stringify(buildTime),
  },
  plugins: [
    VitePWA({
      // On preview builds this replaces the whole PWA below with a self-
      // destroying worker (see `isPreview` above); everything else here is the
      // prod config. Kept first so it's obvious the PWA is off for previews.
      selfDestroying: isPreview,
      // "prompt" (not "autoUpdate"): a new deploy leaves the fresh worker in
      // the "waiting" state instead of silently taking over, so the app can
      // surface an explicit "Update available" button (onNeedRefresh) that the
      // user clicks to activate it and reload. See src/Main.res.
      registerType: "prompt",
      // We register the SW ourselves from the app via `virtual:pwa-register`
      // (with a relative URL so the scope follows the Pages subpath); don't let
      // the plugin inject its own registration script.
      injectRegister: false,
      // Static PNGs live in public/ and are copied to the app root; make sure
      // they're precached alongside the built JS/CSS/HTML.
      includeAssets: [
        "icon.svg",
        "icon-192.png",
        "icon-512.png",
        "icon-maskable-512.png",
        "apple-touch-icon.png",
      ],
      manifest: {
        name: "Sleight",
        short_name: "Sleight",
        description: "An installable, offline-capable FreeCell solitaire.",
        // Relative so they resolve against the manifest URL and inherit the
        // GitHub Pages subpath.
        id: "./",
        scope: "./",
        start_url: "./",
        display: "standalone",
        orientation: "portrait",
        theme_color: "#166534",
        background_color: "#0b1220",
        icons: [
          { src: "icon.svg", sizes: "any", type: "image/svg+xml" },
          { src: "icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "icon-512.png", sizes: "512x512", type: "image/png" },
          {
            src: "icon-maskable-512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "maskable",
          },
        ],
      },
      workbox: {
        // Precache the app shell: the built HTML/JS/CSS, the icons, and the
        // self-hosted fonts (issue #114). The `woff2` glob is what makes the
        // vendored Libre Franklin + Sleight Suits faces available on a first
        // offline launch — without it the fonts aren't in the precache manifest
        // and the app would fall back to an OS font offline.
        globPatterns: ["**/*.{js,css,html,png,svg,woff2,webmanifest}"],
        // SPA-style navigation fallback so a launch of the standalone app (or
        // an offline reload) always resolves to the shell.
        navigateFallback: "index.html",
        // The prod SW is served from the Pages project root, so its scope
        // (`/<repo>/`) is an *ancestor* of every PR preview at
        // `/<repo>/pr-preview/pr-N/`. Without this, the SW answers a preview
        // navigation with the *prod* app shell from precache, whose relative
        // `<script src>` then resolves under the preview dir and 404s — the
        // prod build bleeding into a preview URL. Excluding preview paths lets
        // those navigations fall through to the network and load the correct
        // preview shell. (Preview *assets* already pass through: they aren't in
        // the prod precache manifest. Only the navigation fallback needed this.)
        navigateFallbackDenylist: [/\/pr-preview\//],
      },
    }),
  ],
});
