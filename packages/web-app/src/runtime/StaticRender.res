// Serialize an `Html` vnode tree to a static SVG/XML string.
//
// The runtime `Html` module renders vnodes to *live DOM* in the browser; this
// renders the very same vnodes to *markup* — the build-time counterpart used by
// the icon generator (see scripts/generate/icons.mjs) and by `CardRaster`.
// Because the app icon is built from the real `CardArt` vnodes and stringified
// here, the icon can't drift from the on-screen card design: both come from one
// source.
//
// Preact's vnodes are opaque, so this is Preact's own string renderer rather than a
// walk of our own — which is also what keeps markup and screen from drifting, since
// it reads the same typed props the DOM renderer does.
//
// It costs a second Preact package in the bundle graph (~3 KB gzip), because
// `CardRaster` is app code and not only a build script. Worth knowing if the raster
// scene ever stops being worth it.
@module("preact-render-to-string") external toString: Html.vnode => string = "render"
