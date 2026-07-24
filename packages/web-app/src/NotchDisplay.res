// Publishes the "Display content around screen notch" preference (#204) to the CSS
// as a `data-notch-wings` attribute on the document root, the same seam
// `CutoutSide` uses for `data-cutout`. The landscape chrome defaults to placing the
// Menu/Undo rail out in the corner "wings" beside the notch (see the wing-placement
// rules in index.html); this attribute lets a player fall back to a layout clamped
// entirely inside the browser-reported safe area.
//
//   - on  (default, today's layout) — no attribute; the CSS wing-placement rules
//     apply and the rail rides out beside the notch.
//   - off — `data-notch-wings="off"`; the `html[data-notch-wings="off"]` overrides
//     in index.html neutralise the wing negative-margins, so every control stays
//     inside `env(safe-area-inset-*)` on all edges.
//
// A boolean attribute (present ⇔ clamped) would do, but a named value reads clearly
// in the DOM and leaves room to name a third mode later.

@val @scope("document") external documentElement: WebDom.element = "documentElement"

// Reflect the preference. On the default (wings on) we clear the attribute so the
// base CSS governs; off stamps the clamp value the overrides key off.
let setEnabled = (enabled: bool) =>
  enabled
    ? documentElement->WebDom.removeAttribute("data-notch-wings")
    : documentElement->WebDom.setAttribute("data-notch-wings", "off")
