// The win overlay (#121/#264/#289/#302), exercised in isolation now that it's a
// component of its own (#319).
//
// It was reachable before only by playing a board to a win — `TableScene_test` drains
// an almost-won position and `win.spec.mjs` / `share-win.spec.mjs` do it in a real
// browser. Those still hold, and they're what pins that the panel goes *up* at the
// right moment. What they can't cheaply do is vary the panel's own inputs, which is
// where its branches are:
//
// 1. **The time line comes and goes; the tally never does.** A game restored from a
//    save written before the clock existed (#302) has no time to report, and the line
//    is then absent rather than blank — a "0:00" would be a claim, and an empty
//    element would leave a gap where a number used to be.
// 2. **No share, no status line.** The Share button is withheld from a board with no
//    deal to name and from a game the solver played (#291), and when it goes the
//    reserved status slot goes with it — an empty line under a single New Game button
//    is furniture nothing will ever write to.
// 3. **The share's answer lands on that line.** The share resolves a turn later, and
//    the panel renders once (`Html.create` — no re-render to hold state for), so the
//    line is written into through a captured node. That's the one piece of this
//    component that isn't plain markup, and the one worth a test.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest
open TestDom

let render = (~time=None, ~tally="94 moves · 0 undos", ~onNewGame=() => (), ~share=None) =>
  Html.create(WinOverlay.make({time, tally, onNewGame, share}))

// A share that answers with `line`, and records that it was asked.
let sharing = (~line="Link copied to clipboard.", ~asked=ref(0)): option<WinOverlay.share> => Some({
  onShare: () => {
    asked := asked.contents + 1
    Promise.resolve(line)
  },
})

let buttons = panel => panel->findAll(".win-panel__button")->Array.map(text)

describe("WinOverlay", () => {
  test("announces the win and what it cost", () => {
    let panel = render(~tally="94 moves · 0 undos")
    expect(panel->classes)->toBe("win-overlay")
    expect(panel->textIn(".win-panel__title"))->toBe("You win!")
    expect(panel->textIn(".win-panel__stats"))->toBe("94 moves · 0 undos")
  })

  test("shows how long it took, where there's a time to show", () => {
    expect(render(~time=Some("4:07"))->textIn(".win-panel__time"))->toBe("4:07")
    // Absent, not blank: a game saved before the clock existed has nothing to report,
    // and an empty element would hold a gap open under the headline.
    expect(render(~time=None)->has(".win-panel__time"))->toBe(false)
  })

  test("offers New Game alone when there's nothing to share", () => {
    let panel = render(~share=None)
    expect(panel->buttons)->toEqual(["New Game"])
    // The status slot has reserved height (see TableScene.css), so leaving it in with
    // no share to report on would be a blank band under the button.
    expect(panel->has(".win-panel__status"))->toBe(false)
  })

  test("puts Share beside New Game, not under it, when there is", () => {
    let panel = render(~share=sharing())
    expect(panel->buttons)->toEqual(["New Game", "Share"])
    // Both in the one actions row — that's what keeps the panel as wide as its widest
    // line rather than stacking the buttons.
    expect(panel->findAll(".win-panel__actions .win-panel__button")->Array.length)->toBe(2)
    expect(panel->has(".win-panel__status"))->toBe(true)
  })

  test("re-deals from New Game", () => {
    let deals = ref(0)
    let panel = render(~onNewGame=() => deals := deals.contents + 1)
    panel->find(".win-panel__button")->Option.forEach(click)
    expect(deals.contents)->toBe(1)
  })

  testAsync("reports where the link went, on the line kept for it", async () => {
    let asked = ref(0)
    let panel = render(~share=sharing(~line="Shared.", ~asked))

    // Empty until asked — the slot is held open, not pre-filled.
    expect(panel->textIn(".win-panel__status"))->toBe("")

    panel->find(".win-panel__button--share")->Option.forEach(click)
    expect(asked.contents)->toBe(1)

    // The share resolves a microtask later; the line is written into the node the
    // panel captured as it rendered.
    await Promise.resolve()
    expect(panel->textIn(".win-panel__status"))->toBe("Shared.")
  })

  test("speaks the status line, since nothing else announces the outcome", () => {
    // `aria-live` is the whole mechanism: no dialog is raised and focus doesn't move,
    // so a screen reader would otherwise never learn the share happened.
    expect(
      render(~share=sharing())
      ->find(".win-panel__status")
      ->Option.flatMap(line => line->attr("aria-live")),
    )->toBe(Some("polite"))
  })
})
