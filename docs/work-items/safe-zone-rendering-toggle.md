# Settings toggle: let content render into the safe-area "wings"

**Type:** Work item (draft — file as a GitHub issue when picked up)
**Area:** `packages/web-app` — layout / settings
**Depends on:** the existing safe-area work (#179 clamp, `CutoutSide`, the
Settings screen #191)

## Background

Today the web app is deliberately conservative about display cutouts. With
`viewport-fit=cover` set (`index.html`), it then pads everything back inside the
browser-reported safe rectangle:

- `body` is padded by `env(safe-area-inset-*)` on every edge, and
- `.drop-rows` is pinned inside `left/right: env(safe-area-inset-*)` (#179),

so **all real content stays inside the safe zone**. The only things that
intentionally use the space *outside* it are the top-bar **Menu** button and the
**Undo** control, which are pushed into the corner "wings" beside the notch in
landscape (see the `data-cutout` handling in `index.html` and `CutoutSide`).

The consequence: on a notched iPhone in **landscape**, iOS reports symmetric
horizontal insets (e.g. L50 R50) that reserve the whole notch *strip* on both
sides. Those insets shrink the playfield, so the card table is sized smaller
than it needs to be and the wing regions — which are physically visible screen,
just beside the notch — sit empty. A player who's fine using that space has no
way to opt in.

## Proposal

Add a **Settings** toggle that controls whether the app attempts to render
content **outside the safe zone** — reclaiming the wings for the playfield —
while still keeping legible/interactive content clear of the actual cutout.

Default **off** (today's conservative behaviour is unchanged for anyone who
doesn't flip it).

## What to build

- **Toggle UI** — add a switch to the **Settings** section of the menu
  (`components/Menu.res`), alongside **Auto-collect** and **Hand-placed tilt**.
  Follow the exact same `menu-toggle` / `role="switch"` markup.
- **State + persistence** — wire it through the established pattern:
  - a `Model` field and a `Msg` variant + `update` branch in `Main.res`
    (mirror `ToggleCardTilt` / `ToggleAutoCollect`),
  - persisted via `Preferences.res` under a `pip.<key>` localStorage key
    (e.g. `pip.useWings`), default `false`.
- **Layout behaviour when enabled** — relax the *horizontal* safe-area clamps so
  the stage can use the full width:
  - drop / neutralise the `left/right: env(safe-area-inset-*)` pinning on
    `.drop-rows` (#179) and the corresponding body side-padding, letting the
    height-bounded card sizing grow into the wings.
  - **Keep the actual notch clear.** Cards may enter the wings (physically safe)
    but must not slide *under* the cutout strip. Reuse `CutoutSide` to know which
    side the notch is on so only the clear wing is reclaimed. The Menu/Undo wing
    placement must keep working in both modes.
- **Verification aid** — the existing **Safe-area overlay** debug toggle
  (`CutoutDebug`) should make it easy to eyeball, on-device, that content lands
  in the wings and never under the notch in each state.

## Open questions

- **Label & phrasing** — e.g. "Use full screen", "Extend into the notch wings",
  "Ignore safe area". Prefer wording that signals the playfield gets bigger.
- **Scope of "outside the safe zone"** — a blunt *ignore all insets* (true
  full-bleed) vs. the smarter *cards may use the wings but stay off the notch
  strip*. The requester's note ("uses the wings between the notch on an iPhone")
  points at the smarter, wing-only version; confirm before building.
- **Which axes** — landscape horizontal insets are the clear win; decide whether
  the toggle also affects top/bottom (status bar / home indicator) clearance or
  leaves those clamped.

## Done when

- A **Settings** toggle exists, persisted across launches, defaulting **off**.
- With it **on**, the playfield extends into the safe-area wings on a notched
  iPhone in landscape (cards larger, wing space used) while all content stays
  clear of the cutout itself.
- With it **off**, layout is byte-for-byte today's clamped behaviour.
- Behaviour is covered by tests where practical (in the `CutoutSide_test` mold),
  and `mise run ci` is green.
