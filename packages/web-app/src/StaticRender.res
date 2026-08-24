// Serialize an `Html` vnode tree to a static SVG/XML string.
//
// The runtime `Html` module renders vnodes to *live DOM* in the browser; this
// renders the very same vnodes to *markup* — the build-time counterpart used by
// the icon generator (see scripts/generate/icons.mjs) and by `CardRaster`.
// Because the app icon is built from the real `CardArt` vnodes and stringified
// here, the icon can't drift from the on-screen card design: both come from one
// source.
//
// This used to be a ~40-line walk over our own `vnode` variant, because we owned
// that variant. Preact's vnodes are opaque, so the walk is Preact's own string
// renderer — which reads the same typed props the DOM renderer does, so markup
// and screen can't drift.
//
// It costs a second Preact package in the bundle graph, because `CardRaster` is
// app code and not only a build script: ~3 KB gzip of the swap's total. Worth
// knowing if the raster scene ever stops being worth it.
@module("preact-render-to-string") external toString: Html.vnode => string = "render"
