// The segmented game row, in both of its shapes.
open Vitest
open TestDom

let render = (~label="FreeCell", ~selected=false, ~onSelect=() => (), ~onInfo=?) =>
  Html.create(MenuGameRow.make({label, selected, onSelect, ?onInfo}))

describe("MenuGameRow", () => {
  test("is a bare row, with no wrapper at all, while there is nowhere to go", () => {
    // The flag off. The wrapper is what the segmented look hangs off, so a row that
    // kept one would be a row whose corners are squared against a segment that isn't
    // there.
    let row = render()
    expect(row->tag)->toBe("BUTTON")
    expect(row->classes)->toBe("menu-row menu-row--action")
  })

  test("puts the two segments side by side, as siblings", () => {
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

  test("marks the whole control as the game on the table, not just its name", () => {
    // The highlight is the name segment's, but the border colour has to carry across
    // the "i" or the pair stops reading as one control — which is what the modifier on
    // the wrapper is for.
    let row = render(~selected=true, ~onInfo=() => ())
    expect(row->classes)->toBe("menu-game-row menu-game-row--active")
    expect(row->textIn(".menu-row"))->toBe("FreeCell")
    expect(row->find(".menu-row")->Option.mapOr("", classes))->toBe(
      "menu-row menu-row--action menu-row--active",
    )
  })
})
