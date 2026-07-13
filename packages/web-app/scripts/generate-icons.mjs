// Dependency-free PWA icon generator.
//
// Renders the app emblem (a white spade on a green rounded square) to PNG at
// the sizes the manifest and iOS need, using only Node's built-in `zlib` for
// the PNG DEFLATE stream — no image libraries, so it runs anywhere the repo's
// pinned Node does. Regenerate with `mise run icons`; pass `--preview` to print
// an ASCII rendering of the emblem instead of writing files.
//
// Outputs (into packages/web-app/public/):
//   icon-192.png            any-purpose, rounded, transparent corners
//   icon-512.png            any-purpose, rounded, transparent corners
//   icon-maskable-512.png   full-bleed background, emblem inside the safe zone
//   apple-touch-icon.png    180px, full-bleed (iOS masks corners itself)

import { deflateSync } from "node:zlib";
import { writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const OUT_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "public");

// Brand colors — keep in sync with the manifest theme/background in vite.config.js.
const GREEN = [22, 101, 52]; // #166534
const WHITE = [255, 255, 255];

// --- PNG encoding -----------------------------------------------------------

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const typeBuf = Buffer.from(type, "latin1");
  const lenBuf = Buffer.alloc(4);
  lenBuf.writeUInt32BE(data.length, 0);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([lenBuf, typeBuf, data, crcBuf]);
}

function encodePng(width, height, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type RGBA
  // 10,11,12 = compression/filter/interlace = 0

  // Prepend a zero (filter type "none") to each scanline.
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }

  return Buffer.concat([
    sig,
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// --- Emblem geometry --------------------------------------------------------

// A spade in a coordinate system spanning roughly [-1.3, 1.3], y-up, centered
// at the origin. Built from the classic implicit heart curve flipped to point
// up, plus a triangular stem at the bottom.
function inSpade(x, y) {
  // Heart curve (x²+y²−1)³ − x²y³ < 0 points down; negate y so the tip is up.
  const yy = -y;
  const heart = Math.pow(x * x + yy * yy - 1, 3) - x * x * yy * yy * yy;
  if (heart < 0) return true;
  // Stem: a small triangle flaring out below the lobes.
  if (y < -0.55 && y > -1.15) {
    const halfWidth = 0.08 + 0.55 * (-0.55 - y);
    if (Math.abs(x) < halfWidth) return true;
  }
  return false;
}

function rounded(px, py, size, radius) {
  // Signed test for a rounded square covering [0,size)².
  const r = radius;
  const cx = Math.min(Math.max(px, r), size - r);
  const cy = Math.min(Math.max(py, r), size - r);
  const dx = px - cx;
  const dy = py - cy;
  return dx * dx + dy * dy <= r * r;
}

// Render one icon. `cornerRadius` is a fraction of size (0 = square/full-bleed);
// `emblemScale` sizes the spade relative to the icon.
function render(size, { cornerRadius = 0, emblemScale = 0.62 } = {}) {
  const SS = 4; // supersampling factor for smooth edges
  const rgba = Buffer.alloc(size * size * 4);
  const radiusPx = cornerRadius * size;
  const emblemHalf = (emblemScale * size) / 2;
  const cx = size / 2;
  const cy = size / 2;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let bgCov = 0;
      let fgCov = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const px = x + (sx + 0.5) / SS;
          const py = y + (sy + 0.5) / SS;
          if (radiusPx > 0 ? rounded(px, py, size, radiusPx) : true) bgCov++;
          // Emblem coords: center, y-up, scaled. Nudge up slightly so the
          // stem has room and the shape reads as centered.
          const ex = (px - cx) / emblemHalf;
          const ey = -(py - cy - size * 0.04) / emblemHalf;
          if (inSpade(ex, ey)) fgCov++;
        }
      }
      const total = SS * SS;
      const i = (y * size + x) * 4;
      const bgA = bgCov / total;
      const fgA = fgCov / total;
      // Composite: green background, white spade on top.
      const r = GREEN[0] * (1 - fgA) + WHITE[0] * fgA;
      const g = GREEN[1] * (1 - fgA) + WHITE[1] * fgA;
      const b = GREEN[2] * (1 - fgA) + WHITE[2] * fgA;
      // Alpha is the background coverage (rounded corners become transparent);
      // where the emblem sits it's always fully opaque.
      const a = Math.max(bgA, fgA);
      rgba[i] = Math.round(r);
      rgba[i + 1] = Math.round(g);
      rgba[i + 2] = Math.round(b);
      rgba[i + 3] = Math.round(a * 255);
    }
  }
  return encodePng(size, size, rgba);
}

function preview() {
  const W = 48;
  const H = 40;
  let out = "";
  for (let row = 0; row < H; row++) {
    for (let col = 0; col < W; col++) {
      const ex = (col / W) * 2.6 - 1.3;
      const ey = -((row / H) * 2.6 - 1.3);
      out += inSpade(ex, ey) ? "#" : ".";
    }
    out += "\n";
  }
  process.stdout.write(out);
}

if (process.argv.includes("--preview")) {
  preview();
} else {
  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(join(OUT_DIR, "icon-192.png"), render(192, { cornerRadius: 0.18 }));
  writeFileSync(join(OUT_DIR, "icon-512.png"), render(512, { cornerRadius: 0.18 }));
  // Maskable: no rounded corners, emblem shrunk into the ~80% safe zone.
  writeFileSync(
    join(OUT_DIR, "icon-maskable-512.png"),
    render(512, { cornerRadius: 0, emblemScale: 0.5 }),
  );
  // Apple touch icon: full-bleed square, iOS applies its own corner mask.
  writeFileSync(join(OUT_DIR, "apple-touch-icon.png"), render(180, { cornerRadius: 0 }));
  process.stdout.write(`Wrote icons to ${OUT_DIR}\n`);
}
