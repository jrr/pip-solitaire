// PWA icon generator — built from the *real* cards.
//
// The icon is a trio of cards (7·8·9) fanned over the game's own dark-blue
// background, composed in `IconArt` from the very same `CardArt` vnodes the app
// renders on screen and stringified by `StaticRender`. So there's one source of
// truth for the card design: evolve the card and the icon follows here
// automatically. This script takes that SVG and rasterizes it to the PNG sizes
// the manifest and iOS need.
//
// Because it renders real SVG (fonts, the suit glyphs) it needs a real SVG
// renderer — `@resvg/resvg-js`, as issue #49 anticipated — rather than the
// hand-rolled pixel pusher this file used to be. Run it with `mise run icons`
// (which builds the ReScript first); pass `--svg` to print the master SVG.
//
// Outputs (into packages/web-app/public/):
//   icon.svg                scalable master, rounded — the source of truth
//   icon-192.png            rounded, transparent corners
//   icon-512.png            rounded, transparent corners
//   icon-maskable-512.png   full-bleed background, fan inside the safe zone
//   apple-touch-icon.png    180px, full-bleed (iOS masks the corners itself)

import { Resvg } from "@resvg/resvg-js";
import { writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// The compiled ReScript art. `mise run icons` depends on `build`, so these
// `.res.mjs` siblings exist by the time this runs.
import { standardSvg, maskableSvg, fullBleedSvg } from "../src/IconArt.res.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(HERE, "..", "public");

// The exact fonts the app ships, vendored by `mise run fonts` (issue #114): the
// card ranks are Libre Franklin 600 and the suits are the merged "Sleight Suits"
// subset. resvg reads sfnt (TrueType/OpenType), not the woff2 the browser gets,
// so we point it at the TTFs in src/fonts. Rasterizing from these — with system
// fonts turned *off* — makes the icons deterministic and pixel-for-pixel the
// faces the app renders, instead of whatever sans-serif the build machine has.
const FONT_FILES = [
  join(HERE, "..", "src", "fonts", "libre-franklin-600.ttf"),
  join(HERE, "..", "src", "fonts", "sleight-suits.ttf"),
];

// Rasterize an SVG string to a PNG buffer at the given pixel width (icons are
// square, so height follows).
function raster(svg, size) {
  const resvg = new Resvg(svg, {
    fitTo: { mode: "width", value: size },
    font: { fontFiles: FONT_FILES, loadSystemFonts: false, defaultFontFamily: "Libre Franklin" },
  });
  return resvg.render().asPng();
}

if (process.argv.includes("--svg")) {
  process.stdout.write(standardSvg() + "\n");
} else {
  mkdirSync(OUT_DIR, { recursive: true });

  const standard = standardSvg();
  writeFileSync(join(OUT_DIR, "icon.svg"), standard);
  writeFileSync(join(OUT_DIR, "icon-192.png"), raster(standard, 192));
  writeFileSync(join(OUT_DIR, "icon-512.png"), raster(standard, 512));
  writeFileSync(join(OUT_DIR, "icon-maskable-512.png"), raster(maskableSvg(), 512));
  writeFileSync(join(OUT_DIR, "apple-touch-icon.png"), raster(fullBleedSvg(), 180));

  process.stdout.write(`Wrote icons to ${OUT_DIR}\n`);
}
