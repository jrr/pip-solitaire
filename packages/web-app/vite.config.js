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
        // Precache the app shell: the built HTML/JS/CSS plus the icons.
        globPatterns: ["**/*.{js,css,html,png,svg,webmanifest}"],
        // SPA-style navigation fallback so a launch of the standalone app (or
        // an offline reload) always resolves to the shell.
        navigateFallback: "index.html",
      },
    }),
  ],
});
