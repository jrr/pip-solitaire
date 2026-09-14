// The game row, in each of its shapes.
open Vitest
open TestDom

let render = (~label="FreeCell", ~selected=false, ~onSelect=() => (), ~variant=?, ~onInfo=?) =>
  Html.create(MenuGameRow.make({label, selected, onSelect, ?variant, ?onInfo}))

// A row with a segment on it is a row of a real family, so the mark is a real one rather
// than a string invented here — what the segment shows is `GameVariant`'s claim, tested
// there.
let variantOf = (game, ~onCycle=() => ()): MenuGameRow.variant => {
  mark: Game.variantOf(game)->Option.getOrThrow->GameVariant.forVariant,
  onCycle,
}

describe("MenuGameRow", () => {
  test("is a bare row, with no wrapper at all, while there is nothing beside it", () => {
    // One pack and the flag off. The wrapper is what lays a pair out, so a row that
    // kept one would be reserving space beside itself for nothing.
    let row = render()
    expect(row->tag)->toBe("BUTTON")
    expect(row->classes)->toBe("menu-row menu-row--action")
  })

  test("puts the name and the i side by side, as siblings", () => {
    // The whole point of the shape: a button inside a button is markup the browser
    // rewrites, and the inner tap would reach the outer through bubbling — tapping "i"
    // would switch game on its way to the info screen.
    let row = render(~onInfo=() => ())
    expect(row->children->Array.map(tag))->toEqual(["BUTTON", "BUTTON"])
    expect(row->findAll(".menu-row .menu-game-row__info")->Array.length)->toBe(0)
  })

  test("keeps the two taps apart", () => {
    let log = []
    let row = render(
      ~onSelect=() => log->Array.push("select"),
      ~onInfo=() => log->Array.push("info"),
    )
    row->find(".menu-row")->Option.forEach(click)
    row->find(".menu-game-row__info")->Option.forEach(click)
    expect(log)->toEqual(["select", "info"])
  })

  test("names the game in the info button's accessible name", () => {
    // "Info" alone is one label repeated down the list; the glyph is hidden because the
    // name already carries the word it stands for.
    let row = render(~label="Simple Simon", ~onInfo=() => ())
    let info = row->find(".menu-game-row__info")->Option.getOrThrow
    expect(info->attrOr("aria-label"))->toBe("About Simple Simon")
    expect(info->attrOr("type"))->toBe("button")
    expect(
      row->find(".menu-game-row__badge")->Option.mapOr("", el => el->attrOr("aria-hidden")),
    )->toBe("true")
  })

  test("marks the game on the table on its name, and nowhere else", () => {
    // The highlight belongs to the name button alone. Nothing about the row being
    // current reaches the wrapper or the "i" — which is what keeps the "i" the same
    // mark on the game you're playing as on the ones you aren't.
    let row = render(~selected=true, ~onInfo=() => ())
    expect(row->classes)->toBe("menu-game-row")
    expect(row->textIn(".menu-row"))->toBe("FreeCell")
    expect(row->find(".menu-row")->Option.mapOr("", classes))->toBe(
      "menu-row menu-row--action menu-row--active",
    )
    expect(row->find(".menu-game-row__info")->Option.mapOr("", classes))->toBe(
      "menu-game-row__info",
    )
  })

  test("puts the variant between the name and the i, all three siblings", () => {
    // The same reasoning as the "i": a button inside a button is markup the browser
    // rewrites, and a tap on the segment would switch game on its way to changing it.
    let row = render(~label="Spiderette", ~variant=variantOf(Game.spiderette), ~onInfo=() => ())
    expect(row->children->Array.map(tag))->toEqual(["BUTTON", "BUTTON", "BUTTON"])
    expect(
      row->children->Array.map(classes)->Array.map(list => list->String.includes("__variant")),
    )->toEqual([false, true, false])
  })

  test("keeps the tap that changes the variant off the one that opens the game", () => {
    let log = []
    let row = render(
      ~label="Spiderette",
      ~onSelect=() => log->Array.push("select"),
      ~variant=variantOf(Game.spiderette, ~onCycle=() => log->Array.push("cycle")),
    )
    row->find(".menu-game-row__variant")->Option.forEach(click)
    row->find(".menu-row:not(.menu-game-row__variant)")->Option.forEach(click)
    expect(log)->toEqual(["cycle", "select"])
  })

  test("wears the mark itself, rather than a spelling of it the row keeps", () => {
    // What a pack or a size *looks* like is `MenuVariantMark`'s, tested there; what this
    // row promises is that the segment carries that component and not a copy of it.
    let row = render(~label="Spiderette", ~variant=variantOf(Game.spiderette))
    expect(row->textIn(".menu-game-row__variant"))->toBe("♠♥×2")
    expect(row->findAll(".menu-variant-mark__suits")->Array.length)->toBe(1)
  })

  test("names the game, what varies, and which one — a mark being no subject at all", () => {
    let pack = render(~label="Spiderette", ~variant=variantOf(Game.spiderette4))
    let segment = pack->find(".menu-game-row__variant")->Option.getOrThrow
    expect(segment->attrOr("aria-label"))->toBe("Spiderette pack: 4 suits")
    expect(segment->attrOr("type"))->toBe("button")
    // …and the word case says as much about the other family, so a screen reader hears a
    // control rather than a bare "Micro".
    let size = render(~label="FreeCell", ~variant=variantOf(Game.micro))
    expect(
      size->find(".menu-game-row__variant")->Option.mapOr("", el => el->attrOr("aria-label")),
    )->toBe("FreeCell size: Micro")
  })

  test("carries the highlight across the seam, the variant being a state of the game", () => {
    // The opposite of the "i", which never takes it: the segment is *which* Spiderette
    // you are playing, so it is lit by the same rule the name is.
    let row = render(~label="Spiderette", ~selected=true, ~variant=variantOf(Game.spiderette))
    expect(row->classes)->toBe("menu-game-row menu-game-row--segmented")
    expect(row->find(".menu-game-row__variant")->Option.mapOr("", classes))->toBe(
      "menu-row menu-row--action menu-row--active menu-game-row__variant",
    )
  })

  test("leaves the wrapper unsegmented on a row with one variant to offer", () => {
    // `--segmented` is what the stylesheet joins the two boxes on, so it has to be the
    // presence of the segment and nothing else.
    let row = render(~onInfo=() => ())
    expect(row->classes)->toBe("menu-game-row")
  })

  test("draws the i as a target around a mark, the two sized separately", () => {
    // Two boxes because they answer different questions: the button is what a thumb
    // has to hit and the span is what an eye has to read, and one element sized for
    // both would have to be wrong about one of them. Their sizes are the
    // stylesheet's; that they are distinct elements is this file's.
    let row = render(~onInfo=() => ())
    let info = row->find(".menu-game-row__info")->Option.getOrThrow
    expect(info->children->Array.map(classes))->toEqual(["menu-game-row__badge"])
    expect(row->textIn(".menu-game-row__badge"))->toBe("i")
  })
})
