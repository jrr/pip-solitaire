// The build-version badge tucked into the corner of the chrome: version and
// build time, plus an "offline-ready" suffix once the service worker reports
// its precache is complete.
//
// A component is just a `props => vnode` function. The JSX transform lowers
// `<VersionBadge .../>` to `Html.jsx(VersionBadge.make, props)` and fills this
// record from the attributes. (The `@jsx.component` sugar that would auto-derive
// `props` isn't usable here — it types `make` as the runtime's `element`, i.e. a
// real DOM node, but on this diffing runtime a view is a `vnode` description — so
// we spell the record out, which is all that sugar expands to anyway.) Layout and
// colors for `#version-badge` live in the stylesheet in index.html; here we build
// only structure and state-dependent text.
type props = {version: string, buildTime: string, offlineReady: bool}

let make = ({version, buildTime, offlineReady}) => {
  let label = offlineReady
    ? `v${version} · ${buildTime} · offline-ready`
    : `v${version} · ${buildTime}`
  <div id="version-badge"> {Html.string(label)} </div>
}
