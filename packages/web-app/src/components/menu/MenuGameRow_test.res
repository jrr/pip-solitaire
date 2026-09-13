// The game row, in each of its shapes.
open Vitest
open TestDom

let render = (~label="FreeCell", ~selected=false, ~onSelect=() => (), ~pack=?, ~onInfo=?) =>
  Html.create(MenuGameRow.make({label, selected, onSelect, ?pack, ?onInfo}))

// A row with a pack on it is a Spiderette row, so the mark is a real one rather than a
// string invented here — what the segment shows is `GamePack`'s claim, tested there.
let packOf = (game, ~onCycle=() => ()): MenuGameRow.pack => {
  mark: GamePack.forDeck(game.Game.deck),
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

  test("puts the pack between the name and the i, all three siblings", () => {
    // The same reasoning as the "i": a button inside a button is markup the browser
    // rewrites, and a tap on the pack would switch game on its way to changing it.
    let row = render(~label="Spiderette", ~pack=packOf(Game.spiderette), ~onInfo=() => ())
    expect(row->children->Array.map(tag))->toEqual(["BUTTON", "BUTTON", "BUTTON"])
    expect(
      row->children->Array.map(classes)->Array.map(list => list->String.includes("pack")),
    )->toEqual([false, true, false])
  })

  test("keeps the tap that changes the pack off the one that opens the game", () => {
    let log = []
    let row = render(
      ~label="Spiderette",
      ~onSelect=() => log->Array.push("select"),
      ~pack=packOf(Game.spiderette, ~onCycle=() => log->Array.push("cycle")),
    )
    row->find(".menu-game-row__pack")->Option.forEach(click)
    row->find(".menu-row:not(.menu-game-row__pack)")->Option.forEach(click)
    expect(log)->toEqual(["cycle", "select"])
  })

  test("shows the pips, and a multiplier only where there is more than one pack", () => {
    let row = render(~label="Spiderette", ~pack=packOf(Game.spiderette))
    expect(row->textIn(".menu-game-row__suits"))->toBe("♠♥")
    expect(row->textIn(".menu-game-row__copies"))->toBe("×2")
    // The standard pack, once: four suits and nothing after them.
    let standard = render(~label="Spiderette", ~pack=packOf(Game.spiderette4))
    expect(standard->textIn(".menu-game-row__suits"))->toBe("♠♥♦♣")
    expect(standard->findAll(".menu-game-row__copies")->Array.length)->toBe(0)
  })

  test("names the game and the pack it is wearing, the pips being unspeakable", () => {
    let row = render(~label="Spiderette", ~pack=packOf(Game.spiderette4))
    let pack = row->find(".menu-game-row__pack")->Option.getOrThrow
    expect(pack->attrOr("aria-label"))->toBe("Spiderette pack: 4 suits")
    expect(pack->attrOr("type"))->toBe("button")
  })

  test("carries the highlight across the seam, the pack being a state of the game", () => {
    // The opposite of the "i", which never takes it: the pack is *which* Spiderette
    // you are playing, so it is lit by the same rule the name is.
    let row = render(~label="Spiderette", ~selected=true, ~pack=packOf(Game.spiderette))
    expect(row->classes)->toBe("menu-game-row menu-game-row--packed")
    expect(row->find(".menu-game-row__pack")->Option.mapOr("", classes))->toBe(
      "menu-row menu-row--action menu-row--active menu-game-row__pack",
    )
  })

  test("leaves the wrapper unpacked on a game played with one pack", () => {
    // `--packed` is what the stylesheet joins the two boxes on, so it has to be the
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
