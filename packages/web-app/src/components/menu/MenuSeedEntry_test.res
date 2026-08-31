// The menu's "Enter seed" control.
//
// The far end of Share Seed's link: what makes a number read off another screen
// worth showing is that this deals it. So the cases are about which text counts as
// a number and what reaches the caller — the parse itself is `Command`'s, and
// `Command_test` pins it.
open Vitest
open TestDom

let render = (~seed="", ~onSeed=_ => (), ~onDeal=_ => ()) =>
  Html.create(MenuSeedEntry.make({seed, onSeed, onDeal}))

let field = (entry): element => entry->find(".menu-seed__field")->Option.getExn
let deal = (entry): element => entry->find(".menu-seed__deal")->Option.getExn

describe("MenuSeedEntry", () => {
  test("shows the seed it was given, since the field holds nothing of its own", () => {
    // Controlled: the text is the chrome's, written in here every render. A field
    // that kept its own would drift from the model that submits it.
    expect(render(~seed="24680")->field->value)->toBe("24680")
  })

  test("reports each keystroke without interpreting it", () => {
    // Even "12abc": the model holds the *text*, and it's the button below that
    // decides whether there's a deal in it.
    let typed = []
    let entry = render(~onSeed=text => typed->Array.push(text))
    entry->field->typeInto("12abc")
    expect(typed)->toEqual(["12abc"])
  })

  test("deals the number that was typed", () => {
    let dealt = []
    let entry = render(~seed=" 24680 ", ~onDeal=seed => dealt->Array.push(seed))
    entry->submit
    // Trimmed, and an `int` rather than the text: a caller has no parse to repeat.
    expect(dealt)->toEqual([24680])
  })

  test("offers no deal until the field holds one", () => {
    // The real `disabled` attribute, so an empty field's Deal can't be pressed at
    // all — and digits-only, which is `Command.dealNumber`'s rule: "12abc" would
    // otherwise read as 12 and open a board nobody asked for.
    expect(render(~seed="")->deal->hasAttr("disabled"))->toBe(true)
    expect(render(~seed="12abc")->deal->hasAttr("disabled"))->toBe(true)
    expect(render(~seed="24680")->deal->hasAttr("disabled"))->toBe(false)
  })

  test("deals nothing when what's typed isn't a number", () => {
    // The button being disabled is the visible half; this is the other. Enter
    // submits the form directly, so the guard has to be on the submit as well.
    let dealt = []
    let entry = render(~seed="12abc", ~onDeal=seed => dealt->Array.push(seed))
    entry->submit
    expect(dealt)->toEqual([])
  })

  test("asks a phone for the number pad, and for none of its prose helpers", () => {
    // A deal number is digits, not a word: autocomplete has nothing useful to
    // offer it, and a text keyboard would make the common case a hunt.
    let field = render()->field
    expect(field->attrOr("inputmode"))->toBe("numeric")
    expect(field->attrOr("autocomplete"))->toBe("off")
  })
})
