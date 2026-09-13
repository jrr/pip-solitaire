// The game row, in both of its shapes.
open Vitest
open TestDom

let render = (~label="FreeCell", ~selected=false, ~onSelect=() => (), ~onInfo=?) =>
  Html.create(MenuGameRow.make({label, selected, onSelect, ?onInfo}))

describe("MenuGameRow", () => {
  test("is a bare row, with no wrapper at all, while there is nowhere to go", () => {
    // The flag off. The wrapper is what lays the pair out, so a row that kept one
    // would be reserving space beside itself for an "i" that isn't there.
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
