// The menu's banded group (`MenuSection`), and with it the one thing no other
// component here does: **taking children**.
//
// Children are a props field like any other — the JSX transform fills
// `children?: Html.vnode` from whatever sits between the tags — but three shapes reach
// that one field (one child, several, and a mapped list through `Html.array`), which is
// why there is a case here per shape. The tag choice and the accessible name are pinned
// here too, since both are invisible on screen and neither has a test elsewhere.
open Vitest
open TestDom

let row = label => <span className="row"> {Html.string(label)} </span>

// The first row's text — enough to say *what* landed inside a single-child
// section, without asserting on the row itself.
let rowText = (section: Html.element) => section->textIn(".row")

describe("MenuSection", () => {
  test("is a div by default, and a nav where the rows go somewhere", () => {
    expect(Html.create(MenuSection.make({label: "Settings"}))->tag)->toBe("DIV")
    expect(Html.create(MenuSection.make({label: "More", tag: Nav}))->tag)->toBe("NAV")
  })

  test("names itself for assistive tech, or stays anonymous with no label", () => {
    let named = Html.create(MenuSection.make({label: "Debug"}))
    expect(named->attr("aria-label"))->toBe(Some("Debug"))

    // The bottom band is a layout group, not a named region: naming it would
    // announce a position rather than a purpose.
    let anonymous = Html.create(MenuSection.make({modifier: "menu-section--bottom"}))
    expect(anonymous->hasAttr("aria-label"))->toBe(false)
    expect(anonymous->attr("class"))->toBe(Some("menu-section menu-section--bottom"))
  })

  test("shows a heading only where one was asked for", () => {
    let headed = Html.create(MenuSection.make({label: "game", heading: "game"}))
    expect(
      headed
      ->find(".menu-section__heading")
      ->Option.mapOr("", text),
    )->toBe("game")

    let unheaded = Html.create(MenuSection.make({label: "Settings"}))
    expect(unheaded->find(".menu-section__heading")->Option.isSome)->toBe(false)
  })

  test("lets the heading name a number, keeping a space in front of it", () => {
    // The accessible name is the visible text, so this one space is all that stands
    // between the words and the digits when a screen reader runs them together —
    // "this game24680" without it.
    let named = Html.create(
      MenuSection.make({label: "this game", heading: "this game", headingValue: "24680"}),
    )
    expect(named->textIn(".menu-section__heading"))->toBe("this game 24680")
    // Its own element, so CSS can set the digits in mono rather than in the heading's
    // uppercased sans.
    expect(named->textIn(".menu-section__value"))->toBe("24680")
  })

  test("leaves no empty value element behind when there's no number to name", () => {
    // It would show as a stray gap after the heading, and read as one to a screen
    // reader — a board with no seed has nothing to say here at all.
    let bare = Html.create(MenuSection.make({label: "this game", heading: "this game"}))
    expect(bare->textIn(".menu-section__heading"))->toBe("this game")
    expect(bare->find(".menu-section__value")->Option.isSome)->toBe(false)
  })

  test("holds a single child", () => {
    let section = Html.create(<MenuSection label="Games"> {row("only")} </MenuSection>)
    expect(section->childCount)->toBe(1)
    expect(section->rowText)->toBe("only")
  })

  test("holds several children, in the order they were written", () => {
    let section = Html.create(
      <MenuSection label="Debug" tag=Nav>
        {row("first")}
        {row("second")}
        {row("third")}
      </MenuSection>,
    )
    expect(section->childCount)->toBe(3)
    expect(section->text)->toBe("firstsecondthird")
  })

  test("splices a mapped list in rather than nesting it", () => {
    let section = Html.create(
      <MenuSection label="Games"> {["a", "b", "c"]->Array.map(row)->Html.array} </MenuSection>,
    )
    // Three siblings, not one wrapper holding three: `Html.array` is `%identity`, so a
    // list of children is the same thing to the runtime as children written out one by
    // one — which is why a section built from a mapped list and one built from
    // written-out rows are indistinguishable in the DOM.
    expect(section->childCount)->toBe(3)
    expect(section->text)->toBe("abc")
  })

  test("takes a heading and children together, heading first", () => {
    let section = Html.create(
      <MenuSection label="game" heading="game">
        {row("New")}
        {row("Restart")}
      </MenuSection>,
    )
    expect(section->childCount)->toBe(3)
    expect(section->text)->toBe("gameNewRestart")
  })

  test("is legal with no children at all", () => {
    let empty = Html.create(MenuSection.make({label: "Updates"}))
    expect(empty->childCount)->toBe(0)
  })
})
