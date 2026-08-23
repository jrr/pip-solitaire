// Serialize an `Html` vnode tree to a static SVG/XML string.
//
// The runtime `Html` module renders vnodes to *live DOM* in the browser; this
// renders the very same vnodes to *markup* — the build-time counterpart used by
// the icon generator (see scripts/generate/icons.mjs) and by `CardRaster`.
// Because the app icon is built from the real `CardArt` vnodes and stringified
// here, the icon can't drift from the on-screen card design: both come from one
// source.
//
// SPIKE (Preact): this used to be a ~40-line walk over our own `vnode` variant,
// because we owned that variant. Preact's vnodes are opaque, so the walk is now
// Preact's own string renderer. It honours the `attrs` shim (`attrsShim.mjs`
// installs its hook on the shared `options` object, which the string renderer
// reads too), so the generic attribute map serializes exactly as it did.
//
// The cost is a second Preact package in the bundle graph — `CardRaster` is app
// code, not just a build script — which is one of the numbers this spike exists
// to put a figure on.
// The `attrs` hook has to be installed here as well as in `Html`: this module is
// reachable without it (the icon generator and `CardRaster` never render to the
// DOM), and a vnode built before the hook is installed keeps its raw pair-list.
@module("./attrsShim.mjs") external installAttrsShim: unit => unit = "install"
installAttrsShim()

@module("preact-render-to-string") external renderToString: Html.vnode => string = "render"

// Wrapped in a `let` rather than exposed as the external directly, and that is
// load-bearing: ReScript inlines an external at its call site, so callers would
// import `preact-render-to-string` and never import *this* module — leaving the
// `attrs` hook above uninstalled in exactly the paths that need it.
let toString = vnode => renderToString(vnode)
