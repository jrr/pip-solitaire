// Vendored-font generator — the self-hosted, offline-precached type the app and
// cards render with. It regenerates every font file the app ships,
// so the faces are reproducible from their upstream `@fontsource` sources rather
// than opaque binaries checked in by hand — the same task-interface convention
// as `mise run icons`. Run it with `mise run fonts`. The outputs are
// byte-reproducible: a re-run against the same sources leaves `git status`
// clean, so a diff in a font file means the face itself changed.
//
// Two faces, both SIL Open Font License:
//
//   Libre Franklin  — the chrome (400) and the card rank labels (600). The
//                     upstream `@fontsource/libre-franklin` already ships a
//                     Latin subset per weight, which is all we need, so those
//                     woff2 files are copied straight through.
//
//   Pip Suits   — the four card pips ♠ ♣ ♥ ♦ (U+2660 U+2663 U+2665 U+2666).
//                     The stock IBM Plex Sans distribution has no card suits;
//                     the *JP* distribution carries the Miscellaneous Symbols
//                     block, but splits it across two of its many subset files
//                     (♠ ♣ ♦ in one, ♥ in another). We subset each to just its
//                     suits and merge the four glyphs into one tiny face,
//                     renamed to the distinct family "Pip Suits" — the name
//                     keeps the font stack unambiguous and sidesteps the OFL
//                     Reserved Font Name on "IBM Plex" for this carved subset.
//
// Outputs:
//   public/fonts/*.woff2   shipped + precached for the browser (see vite.config.js)
//   src/fonts/*.ttf        build-only TrueType for the resvg icon rasterizer
//                          (resvg reads sfnt, not woff2 — see generate-icons.mjs)
//   public/fonts/OFL-*.txt the upstream license texts, vendored with the fonts

import subsetFont from "subset-font";
import opentype from "opentype.js";
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const webAppRoot = join(here, "..", "..");
const fontsource = join(webAppRoot, "node_modules", "@fontsource");
const publicFonts = join(webAppRoot, "public", "fonts");
const srcFonts = join(webAppRoot, "src", "fonts");

// The Latin glyphs the resvg rasterizer needs for the icon's card ranks. The
// icon shows 7·8·9, but keep every rank label so the build font matches any card
// the icon composer might draw. (The browser gets the full Latin subset via the
// copied woff2; this narrower set is only for the icon's TrueType.)
const rankChars = "A234567891JQK0";

// The four card suits and which JP subset file carries each. `pyftsubset` /
// glyphhanger would read a full font; @fontsource ships the JP face pre-split,
// so we point at the two subsets that hold the suits (see unicode.json upstream).
const suits = [
  { ch: "♠", subset: 56 },
  { ch: "♣", subset: 56 },
  { ch: "♦", subset: 56 },
  { ch: "♥", subset: 86 },
];

const toArrayBuffer = (buf) => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);

// The sfnt checksum: the big-endian uint32 sum over a byte range, zero-padded to
// a multiple of four. Font-file length and table offsets are already 4-aligned.
function checkSum(buf, start, length) {
  let sum = 0;
  for (let i = start; i < start + length; i += 4) {
    let word = 0;
    for (let j = 0; j < 4; j++) {
      word = (word << 8) | (i + j < start + length ? buf[i + j] : 0);
    }
    sum = (sum + (word >>> 0)) >>> 0;
  }
  return sum;
}

// opentype.js stamps `head.created` and `head.modified` with the wall clock on
// every write, and only `created` can be overridden at construction. So the
// merged face — and the woff2 packed from it — would differ on every run even
// when nothing about the face had changed, and `git status` after `mise run
// fonts` could never answer "did the font actually change?". This rewrites both
// dates in place and re-derives the two checksums that cover them: the `head`
// record in the table directory, and `head.checkSumAdjustment`, which is
// computed over the whole file with itself set to zero. `ttf` is a Node Buffer.
function pinHeadDates(ttf, createdSeconds, modifiedSeconds) {
  const numTables = ttf.readUInt16BE(4);
  let head;
  for (let i = 0; i < numTables; i++) {
    const record = 12 + 16 * i;
    if (ttf.toString("latin1", record, record + 4) === "head") {
      head = {
        record,
        offset: ttf.readUInt32BE(record + 8),
        length: ttf.readUInt32BE(record + 12),
      };
    }
  }
  // LONGDATETIME counts seconds from 1904-01-01, not the Unix epoch.
  const macEpoch = 2082844800n;
  ttf.writeBigInt64BE(BigInt(createdSeconds) + macEpoch, head.offset + 20);
  ttf.writeBigInt64BE(BigInt(modifiedSeconds) + macEpoch, head.offset + 28);
  ttf.writeUInt32BE(0, head.offset + 8);
  ttf.writeUInt32BE(checkSum(ttf, head.offset, head.length), head.record + 4);
  ttf.writeUInt32BE((0xb1b0afba - checkSum(ttf, 0, ttf.length)) >>> 0, head.offset + 8);
}

async function main() {
  mkdirSync(publicFonts, { recursive: true });
  mkdirSync(srcFonts, { recursive: true });

  // --- Libre Franklin -------------------------------------------------------
  const lfFiles = join(fontsource, "libre-franklin", "files");
  for (const weight of [400, 600]) {
    copyFileSync(
      join(lfFiles, `libre-franklin-latin-${weight}-normal.woff2`),
      join(publicFonts, `libre-franklin-${weight}.woff2`),
    );
  }
  // resvg reads TrueType/OpenType, not woff2 — derive a TTF of the rank weight.
  const lf600 = readFileSync(
    join(lfFiles, "libre-franklin-latin-600-normal.woff2"),
  );
  writeFileSync(
    join(srcFonts, "libre-franklin-600.ttf"),
    await subsetFont(lf600, rankChars, { targetFormat: "sfnt" }),
  );

  // --- Pip Suits (merged from the two JP subsets) -----------------------
  const jpFiles = join(fontsource, "ibm-plex-sans-jp", "files");
  const glyphs = [
    // A .notdef at glyph 0 is required by the sfnt spec.
    new opentype.Glyph({
      name: ".notdef",
      unicode: 0,
      advanceWidth: 1000,
      path: new opentype.Path(),
    }),
  ];
  let metrics;
  for (const { ch, subset } of suits) {
    const src = readFileSync(
      join(jpFiles, `ibm-plex-sans-jp-${subset}-400-normal.woff2`),
    );
    const sfnt = await subsetFont(src, ch, { targetFormat: "sfnt" });
    const font = opentype.parse(toArrayBuffer(sfnt));
    // The vertical metrics and the head dates both carry over from the parent
    // face: the outlines are IBM Plex Sans JP's, so its dates are the honest
    // ones — and, unlike the clock, they only move when the upstream package does.
    metrics ??= {
      unitsPerEm: font.unitsPerEm,
      ascender: font.ascender,
      descender: font.descender,
      created: font.tables.head.created,
      modified: font.tables.head.modified,
    };
    const glyph = font.charToGlyph(ch);
    glyphs.push(
      new opentype.Glyph({
        name:
          glyph.name ?? `uni${ch.codePointAt(0).toString(16).toUpperCase()}`,
        unicode: ch.codePointAt(0),
        advanceWidth: glyph.advanceWidth,
        path: glyph.path,
      }),
    );
  }
  const suitFont = new opentype.Font({
    familyName: "Pip Suits",
    styleName: "Regular",
    unitsPerEm: metrics.unitsPerEm,
    ascender: metrics.ascender,
    descender: metrics.descender,
    glyphs,
  });
  const suitTtf = Buffer.from(suitFont.toArrayBuffer());
  pinHeadDates(suitTtf, metrics.created, metrics.modified);
  writeFileSync(join(srcFonts, "pip-suits.ttf"), suitTtf);
  // Repackage the merged TTF as woff2 for the browser, keeping the renamed
  // name records (harfbuzz drops most name ids unless asked to preserve them).
  writeFileSync(
    join(publicFonts, "pip-suits.woff2"),
    await subsetFont(suitTtf, suits.map((s) => s.ch).join(""), {
      targetFormat: "woff2",
      preserveNameIds: [0, 1, 2, 3, 4, 5, 6, 16, 17],
    }),
  );

  // --- License texts, vendored with the fonts -------------------------------
  copyFileSync(
    join(fontsource, "libre-franklin", "LICENSE"),
    join(publicFonts, "OFL-libre-franklin.txt"),
  );
  copyFileSync(
    join(fontsource, "ibm-plex-sans-jp", "LICENSE"),
    join(publicFonts, "OFL-ibm-plex-sans-jp.txt"),
  );

  process.stdout.write(`Wrote fonts to ${publicFonts} and ${srcFonts}\n`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
