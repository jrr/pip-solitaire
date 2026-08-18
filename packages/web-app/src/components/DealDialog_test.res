// Tests for the deal-number dialog (`DealDialog`) — the menu's Play Seed… destination,
// and the way a number a friend sent gets back into the game.
//
// Two things are worth pinning, and they're the two this file covers.
//
// 1. **What counts as a deal number.** `readSeed` is the whole of the dialog's
//    judgement, and it has to be both lenient in one specific way and strict everywhere
//    else. Lenient: the app's own victory share says "Pip FreeCell #776701", so `#776701`
//    is exactly what a player copies out of the message they were sent, and refusing the
//    notation the app itself prints would be perverse. Strict: `Int.fromString` is
//    `parseInt`-shaped and reads `12abc` as 12 — a dialog that quietly deals a
//    *different* board from the one named is worse than one that admits it didn't
//    understand, because the whole point of the number is that two players end up on
//    the same board.
//
// 2. **The status slot holds its height.** The line under the field is empty until
//    there's a refusal to report. If it appeared out of nothing it would shove the
//    Cancel/Play row down the panel as it arrived — under the thumb already on its way
//    to Play, which is precisely when a refusal is most likely to be on screen.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), with the same structural — not pixel — assertion, since jsdom
// has no layout engine: pin the size-determining tree (tags + nesting) and a collapsing
// slot shows up as a changed skeleton.
open Vitest

@get external tagName: Html.element => string = "tagName"
type htmlCollection
@get external childElements: Html.element => htmlCollection = "children"
@get external collLength: htmlCollection => int = "length"
@send external collItem: (htmlCollection, int) => Html.element = "item"

// The size-determining shape of a rendered subtree: tag + children skeleton, with text
// and attributes stripped. An empty status line still renders its `<p>`, so the skeleton
// is identical in both states; a line that came and went would change it.
let rec skeleton = (el: Html.element): string => {
  let kids = el->childElements
  let parts = []
  for i in 0 to kids->collLength - 1 {
    parts->Array.push(kids->collItem(i)->skeleton)
  }
  let inner = parts->Array.length == 0 ? "" : `(${parts->Array.join(",")})`
  el->tagName ++ inner
}

// **Captured eagerly, one render at a time, and that ordering is load-bearing.** The
// dialog splices in a real `<input>` the module owns (`Html.node`), and `Html.create`
// hands back that very node rather than a copy — so rendering a second tree *moves* the
// field out of the first one. Walking both trees at the end would compare a dialog that
// has a field against a dialog that no longer does. Taking each skeleton before the next
// render exists is what keeps the comparison honest.
let skeletonFor = (~status): string => Html.create(DealDialog.make({open_: true, status}))->skeleton

let emptySlot = skeletonFor(~status=None)
let filledSlot = skeletonFor(~status=Some("Not a deal number."))

describe("DealDialog.readSeed", () => {
  test("reads a plain deal number", () =>
    expect(DealDialog.readSeed("776701"))->toEqual(DealDialog.Seed(776701))
  )

  // The notation the app itself prints, in the message it composes
  // (`ShareLink.victoryMessage`) — so it's what lands on a player's clipboard.
  test("accepts the # the victory share puts in front of the number", () =>
    expect(DealDialog.readSeed("#776701"))->toEqual(DealDialog.Seed(776701))
  )

  test("ignores surrounding whitespace, and space after the #", () => {
    expect(DealDialog.readSeed("  776701 "))->toEqual(DealDialog.Seed(776701))
    expect(DealDialog.readSeed("# 776701"))->toEqual(DealDialog.Seed(776701))
  })

  test("keeps leading zeros meaning the same number", () =>
    expect(DealDialog.readSeed("007"))->toEqual(DealDialog.Seed(7))
  )

  test("reads deal 0 as a deal, not as nothing", () =>
    expect(DealDialog.readSeed("0"))->toEqual(DealDialog.Seed(0))
  )

  test("treats an empty field — and a bare # — as blank rather than wrong", () => {
    expect(DealDialog.readSeed(""))->toEqual(DealDialog.Blank)
    expect(DealDialog.readSeed("   "))->toEqual(DealDialog.Blank)
    expect(DealDialog.readSeed("#"))->toEqual(DealDialog.Blank)
  })

  // The regression that motivates hand-checking the digits instead of leaning on
  // `Int.fromString`: `parseInt("12abc")` is 12, so the lazy version would deal board 12
  // to a player who asked for something else entirely and say nothing about it.
  test("refuses a number with anything else stuck to it", () => {
    expect(DealDialog.readSeed("12abc"))->toEqual(DealDialog.Invalid)
    expect(DealDialog.readSeed("12 34"))->toEqual(DealDialog.Invalid)
    expect(DealDialog.readSeed("1e6"))->toEqual(DealDialog.Invalid)
  })

  test("refuses a negative, which names no board", () =>
    expect(DealDialog.readSeed("-5"))->toEqual(DealDialog.Invalid)
  )

  // Long enough to overflow an int is long enough that it isn't a deal number someone
  // was given; refusing keeps a pasted essay out of `Int.fromString`.
  test("refuses a run of digits too long to be a deal", () =>
    expect(DealDialog.readSeed("12345678901234"))->toEqual(DealDialog.Invalid)
  )
})

describe("DealDialog status slot", () => {
  test("is the same shape empty as it is holding a message", () =>
    expect(emptySlot)->toEqual(filledSlot)
  )

  // Belt to that brace: the slot is only stable because the <p> is rendered
  // unconditionally. A future edit that made it conditional would still satisfy a
  // skeleton comparison between two *conditional* renders if both happened to be
  // filled, so pin that the empty case really does still carry the paragraph.
  test("still renders the status paragraph when there's nothing to report", () =>
    expect(emptySlot->String.includes("P"))->toEqual(true)
  )
})
