import { defineConfig } from "vite";
import { VitePWA } from "vite-plugin-pwa";

// `base: "./"` makes emitted asset URLs relative, so the built site works when
// GitHub Pages serves it from a project subpath (https://<user>.github.io/<repo>/)
// rather than a domain root. Vite resolves the bare `core/…` specifier that the
// compiled ReScript emits via the workspace symlink and bundles the module graph.
//
// PWA note: everything installability-related is kept *relative* on purpose so
// it inherits the GitHub Pages subpath without hardcoding the repo name:
//   - `scope`/`start_url`/`id` are "./" and resolve against the manifest URL
//     (`/<repo>/manifest.webmanifest`), i.e. to `/<repo>/`.
//   - The service worker is emitted at the app root and registered with a
//     relative URL (see index.html), so its scope defaults to `/<repo>/`.
//   - Icon `src`s are relative and resolve next to the manifest.
export default defineConfig({
  base: "./",
  plugins: [
    VitePWA({
      // Regenerate the SW and take over automatically on new deploys.
      registerType: "autoUpdate",
      // We register the SW ourselves in index.html with a relative URL so the
      // scope follows the Pages subpath; don't let the plugin inject its own.
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
