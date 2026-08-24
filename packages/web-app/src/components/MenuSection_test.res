// The menu's banded group (`MenuSection`), and with it the one thing no other
// component here does: **taking children**.
//
// Children are a props field like any other — the JSX transform fills
// `children?: Html.vnode` from whatever sits between the tags — but three
// shapes reach that one field, and the point of this file is that all three
// arrive intact and in order:
//
//   - one child                     → the vnode itself
//   - several children              → an array, still typed `Html.vnode`
//   - `…->Html.array` (a list)      → an array, spliced in rather than nested
//
// The last two are the same thing at runtime, which is exactly why a section
// built from a mapped list and one built from written-out rows are
// indistinguishable in the DOM. Also pinned here: the tag choice (`nav` for rows
// that go somewhere, `div` for controls that act in place) and the accessible
// name, because both are invisible on screen and neither has a test elsewhere.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest

@get external tagName: Html.element => string = "tagName"
@get external textContent: Html.element => string = "textContent"
@get external childElementCount: Html.element => int = "childElementCount"
@send external getAttribute: (Html.element, string) => Nullable.t<string> = "getAttribute"
@send external hasAttribute: (Html.element, string) => bool = "hasAttribute"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"

let row = label => <span className="row"> {Html.string(label)} </span>

// The first row's text — enough to say *what* landed inside a single-child
// section, without asserting on the row itself.
let rowText = (section: Html.element) =>
  section
  ->querySelector(".row")
  ->Nullable.toOption
  ->Option.mapOr("<missing>", textContent)

describe("MenuSection", () => {
  test("is a div by default, and a nav where the rows go somewhere", () => {
    expect(Html.create(MenuSection.make({label: "Settings"}))->tagName)->toBe("DIV")
    expect(Html.create(MenuSection.make({label: "More", tag: Nav}))->tagName)->toBe("NAV")
  })

  test("names itself for assistive tech, or stays anonymous with no label", () => {
    let named = Html.create(MenuSection.make({label: "Debug"}))
    expect(named->getAttribute("aria-label")->Nullable.toOption)->toBe(Some("Debug"))

    // The bottom band is a layout group, not a named region: naming it would
    // announce a position rather than a purpose.
    let anonymous = Html.create(MenuSection.make({modifier: "menu-section--bottom"}))
    expect(anonymous->hasAttribute("aria-label"))->toBe(false)
    expect(anonymous->getAttribute("class")->Nullable.toOption)->toBe(
      Some("menu-section menu-section--bottom"),
    )
  })

  test("shows a heading only where one was asked for", () => {
    let headed = Html.create(MenuSection.make({label: "game", heading: "game"}))
    expect(
      headed
      ->querySelector(".menu-section__heading")
      ->Nullable.toOption
      ->Option.mapOr("", textContent),
    )->toBe("game")

    let unheaded = Html.create(MenuSection.make({label: "Settings"}))
    expect(
      unheaded->querySelector(".menu-section__heading")->Nullable.toOption->Option.isSome,
    )->toBe(false)
  })

  test("holds a single child", () => {
    let section = Html.create(<MenuSection label="Games"> {row("only")} </MenuSection>)
    expect(section->childElementCount)->toBe(1)
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
    expect(section->childElementCount)->toBe(3)
    expect(section->textContent)->toBe("firstsecondthird")
  })

  test("splices a mapped list in rather than nesting it", () => {
    let section = Html.create(
      <MenuSection label="Games"> {["a", "b", "c"]->Array.map(row)->Html.array} </MenuSection>,
    )
    // Three siblings, not one wrapper holding three: `Html.array` is `%identity`,
    // so a list of children is the same thing to the runtime as children written
    // out one by one.
    expect(section->childElementCount)->toBe(3)
    expect(section->textContent)->toBe("abc")
  })

  test("takes a heading and children together, heading first", () => {
    let section = Html.create(
      <MenuSection label="game" heading="game">
        {row("New")}
        {row("Restart")}
      </MenuSection>,
    )
    expect(section->childElementCount)->toBe(3)
    expect(section->textContent)->toBe("gameNewRestart")
  })

  test("is legal with no children at all", () => {
    let empty = Html.create(MenuSection.make({label: "Updates"}))
    expect(empty->childElementCount)->toBe(0)
  })
})
