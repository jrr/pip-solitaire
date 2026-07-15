// Serialize an `Html` vnode tree to a static SVG/XML string.
//
// The runtime `Html` module renders vnodes to *live DOM* in the browser; this
// renders the very same vnodes to *markup* — the build-time counterpart used by
// the icon generator (see scripts/generate-icons.mjs). Because the app icon is
// built from the real `CardArt` vnodes and stringified here, the icon can't
// drift from the on-screen card design: both come from one source.
//
// It covers exactly what the card/icon vnodes use — elements with an optional
// `id`/`className` and the generic `attrs` map, plus text and groups. `VRaw`
// (an externally-owned live DOM node) has no static form, so it serializes to
// nothing; the static art never produces one.

let escapeText = s =>
  s
  ->String.replaceAll("&", "&amp;")
  ->String.replaceAll("<", "&lt;")
  ->String.replaceAll(">", "&gt;")

let escapeAttr = s =>
  s
  ->String.replaceAll("&", "&amp;")
  ->String.replaceAll("\"", "&quot;")

let attrsString = (props: Html.elementProps) => {
  let parts = []
  switch props.id {
  | Some(v) => parts->Array.push(`id="${escapeAttr(v)}"`)
  | None => ()
  }
  switch props.className {
  | Some(v) => parts->Array.push(`class="${escapeAttr(v)}"`)
  | None => ()
  }
  props.attrs
  ->Option.getOr([])
  ->Array.forEach(((k, v)) => parts->Array.push(`${k}="${escapeAttr(v)}"`))
  parts->Array.length == 0 ? "" : " " ++ parts->Array.join(" ")
}

let rec toString = (vnode: Html.vnode) =>
  switch vnode {
  | VText(s) => escapeText(s)
  | VGroup(xs) => xs->Array.map(toString)->Array.join("")
  | VRaw(_) => ""
  | VNode({tag, props, children}) =>
    let attrs = attrsString(props)
    let inner = children->Array.map(toString)->Array.join("")
    inner == "" ? `<${tag}${attrs}/>` : `<${tag}${attrs}>${inner}</${tag}>`
  }
