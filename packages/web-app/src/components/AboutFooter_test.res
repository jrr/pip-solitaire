// The `AboutFooter`: its size stability — the footer has to be the same height whether
// or not an update is waiting, or it shoves the version line and everything above it the
// moment an update arrives (see `AboutFooter.res`) — and the order of the two things in
// it, the controls over the build string they are about.
//
// See `RefreshControl_test` for why the size assertion is structural rather than
// pixel-measured.
open Vitest
open TestDom

// The size-determining shape of a rendered subtree: tag + children skeleton, with
// text and attributes stripped. A button hidden with `visibility` keeps its box
// (so the skeleton is unchanged); one hidden with `display: none` would not — but
// the browser still reports the element, so the skeleton alone can't catch a
// regression to `hidden`. The dedicated attribute check below does.
let rec skeleton = (el: Html.element): string => {
  let parts = el->children->Array.map(skeleton)
  let inner = parts->Array.length == 0 ? "" : `(${parts->Array.join(",")})`
  el->tag ++ inner
}

let render = (~updateVisible): Html.element =>
  Html.create(
    AboutFooter.make({
      version: "1.2.3",
      buildTime: "2026-07-23T20:20:00.000Z",
      updateVisible,
      onReload: () => (),
      // The update-check slot; empty here so the size-stability assertions turn on
      // the update button alone — it's the part whose hiding could reflow the footer.
      refresh: Html.empty,
      onOpenAbout: () => (),
    }),
  )

// The same footer with both halves of the actions row filled, for the order and the
// wiring below: the update check is a ready-made node in real use, so a stand-in button
// is as much as this file can hand it.
let rendered = (~onOpenAbout=() => ()): Html.element =>
  Html.create(
    AboutFooter.make({
      version: "1.2.3",
      buildTime: "2026-07-23T20:20:00.000Z",
      updateVisible: false,
      onReload: () => (),
      refresh: RefreshControl.make({label: "Check for updates", busy: false, onClick: () => ()}),
      onOpenAbout,
    }),
  )

let button = (footer): option<Html.element> => footer->find(".menu-update__button")

describe("AboutFooter layout", () => {
  test("puts the controls over the build string they are about", () => {
    // A hand comes down here for the two buttons; the version is the caption under them
    // and the half that grows, since the Update button arrives on its line.
    expect(rendered()->children->Array.map(classes))->toEqual([
      "menu-footer__actions",
      "menu-about__row",
    ])
  })

  test("stands the About button beside the update check, and nothing over the pair", () => {
    // No heading: "About" as a caption over a build string says nothing the build string
    // doesn't, and the screen this sits on is already titled. The band's `aria-label` is
    // the half of a heading that was doing work.
    let footer = rendered()
    expect(footer->attrOr("aria-label"))->toBe("About")
    expect(footer->findAll("h2")->Array.length)->toBe(0)
    expect(footer->findAll(".menu-footer__actions > button")->Array.map(text))->toEqual([
      "Check for updates",
      "About",
    ])
  })

  test("the About button asks for the About screen", () => {
    let log = []
    let footer = rendered(~onOpenAbout=() => log->Array.push("about"))
    footer->findAll(".menu-footer__actions > button")->Array.get(1)->Option.forEach(click)
    expect(log)->toEqual(["about"])
  })
})

describe("AboutFooter size stability", () => {
  let noUpdate = render(~updateVisible=false)
  let updateWaiting = render(~updateVisible=true)

  test("renders the identical box skeleton whether or not an update is waiting", () => {
    expect(skeleton(updateWaiting))->toBe(skeleton(noUpdate))
  })

  test("keeps the Update button in the DOM when hidden, so its box stays reserved", () => {
    // Present in both states — reserved with `visibility`, not conjured on arrival.
    expect(noUpdate->button->Option.isSome)->toBe(true)
    expect(updateWaiting->button->Option.isSome)->toBe(true)
  })

  test(
    "hides the button with the visibility class, never the collapsing `hidden` attribute",
    () => {
      // The regression guard: `hidden` (⇒ `display: none`) collapses the box and
      // reflows the footer. The hidden state must reserve with the class instead.
      switch noUpdate->button {
      | Some(b) =>
        expect(b->hasAttr("hidden"))->toBe(false)
        expect(b->classes->String.includes("menu-update--hidden"))->toBe(true)
      | None => expect("button present")->toBe("button missing")
      }
      // When an update is waiting the button is fully shown (no reserve class).
      switch updateWaiting->button {
      | Some(b) => expect(b->classes->String.includes("menu-update--hidden"))->toBe(false)
      | None => expect("button present")->toBe("button missing")
      }
    },
  )
})
