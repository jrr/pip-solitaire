// The "Enter seed" modal.
//
// The far end of Share: what makes a number worth showing on the menu's heading is
// that this deals it. So the cases are about which text counts as a number and what reaches
// the caller — the parse itself is `Command`'s, and `Command_test` pins it — plus the
// two ways out of a modal, which is what a dialog owes over a row in a menu.
open Vitest
open TestDom

let render = (~seed="", ~onSeed=_ => (), ~onDeal=_ => (), ~onLink=_ => (), ~onCancel=() => ()) =>
  Html.create(SeedDialog.make({seed, onSeed, onDeal, onLink, onCancel}))

let field = (dialog): element => dialog->find(".seed-dialog__field")->Option.getOrThrow
let panel = (dialog): element => dialog->find(".seed-dialog__panel")->Option.getOrThrow
let buttons = (dialog): array<element> => dialog->findAll(".seed-dialog__button")

describe("SeedDialog", () => {
  test("shows the seed it was given, since the field holds nothing of its own", () => {
    // Controlled: the text is the chrome's, written in here every render. A field
    // that kept its own would drift from the model that submits it.
    expect(render(~seed="24680")->field->value)->toBe("24680")
  })

  test("reports each keystroke without interpreting it", () => {
    // Even "12abc": the model holds the *text*, and it's the button below that
    // decides whether there's a deal in it.
    let typed = []
    let dialog = render(~onSeed=text => typed->Array.push(text))
    dialog->field->typeInto("12abc")
    expect(typed)->toEqual(["12abc"])
  })

  test("deals the number that was typed", () => {
    let dealt = []
    let dialog = render(~seed=" 24680 ", ~onDeal=seed => dealt->Array.push(seed))
    dialog->panel->submit
    // Trimmed, and an `int` rather than the text: a caller has no parse to repeat.
    expect(dealt)->toEqual([24680])
  })

  test("offers no deal until the field holds one", () => {
    // The real `disabled` attribute, so an empty field's Deal can't be pressed at
    // all — and digits-only, which is `Command.dealNumber`'s rule: "12abc" would
    // otherwise read as 12 and open a board nobody asked for.
    let deal = dialog => dialog->buttons->Array.getUnsafe(1)
    expect(render(~seed="")->deal->hasAttr("disabled"))->toBe(true)
    expect(render(~seed="12abc")->deal->hasAttr("disabled"))->toBe(true)
    expect(render(~seed="24680")->deal->hasAttr("disabled"))->toBe(false)
  })

  test("deals nothing when what's typed isn't a number", () => {
    // The button being disabled is the visible half; this is the other. Enter
    // submits the form directly, so the guard has to be on the submit as well.
    let dealt = []
    let dialog = render(~seed="12abc", ~onDeal=seed => dealt->Array.push(seed))
    dialog->panel->submit
    expect(dealt)->toEqual([])
  })

  test("opens a pasted link instead of dealing, and says so on the button", () => {
    let dealt = []
    let opened = []
    let dialog = render(
      ~seed=" https://example.com/pip/?game=simplesimon&seed=7 ",
      ~onDeal=seed => dealt->Array.push(seed),
      ~onLink=pasted => opened->Array.push(pasted),
    )
    expect(dialog->buttons->Array.getUnsafe(1)->text)->toBe("Open")
    dialog->panel->submit
    expect(dealt)->toEqual([])
    expect(opened)->toEqual([ShareLink.Deal({game: Game.simpleSimon, seed: 7})])
  })

  test("offers nothing to open for a link that names no board", () => {
    // A page of the app with no deal in it, and another site entirely: there's no
    // board to open, so the button is as inert as it is over "12abc".
    let deal = dialog => dialog->buttons->Array.getUnsafe(1)
    expect(render(~seed="https://example.com/pip/")->deal->hasAttr("disabled"))->toBe(true)
    expect(render(~seed="https://example.com/?q=7")->deal->hasAttr("disabled"))->toBe(true)
  })

  test("offers both ways out of a modal, and only Cancel is one of them", () => {
    // A dialog that can only be answered is a trap, so the dim behind it dismisses
    // too — and the panel is not the dim, which is why the backdrop is an element of
    // its own rather than a background on the overlay.
    let cancels = ref(0)
    let dialog = render(~onCancel=() => cancels := cancels.contents + 1)
    dialog->buttons->Array.getUnsafe(0)->click
    dialog->find(".seed-dialog__backdrop")->Option.getOrThrow->click
    expect(cancels.contents)->toBe(2)
  })

  test("puts Cancel and Deal in that order, so the action is under the typing hand", () => {
    expect(render(~seed="1")->buttons->Array.map(text))->toEqual(["Cancel", "Deal"])
  })

  test("announces itself as a modal dialog, since it covers everything", () => {
    // The menu is still up behind the dim and the board behind that; without this a
    // screen reader offers both as if they were reachable.
    let dialog = render()
    expect(dialog->attrOr("role"))->toBe("dialog")
    expect(dialog->attrOr("aria-modal"))->toBe("true")
    expect(dialog->attrOr("aria-label"))->toBe("Enter seed")
  })

  test("asks a phone for the number pad, and for none of its prose helpers", () => {
    // A deal number is digits, not a word: autocomplete has nothing useful to
    // offer it, and a text keyboard would make the common case a hunt. A link is
    // pasted rather than typed, which no keyboard stands in the way of.
    let field = render()->field
    expect(field->attrOr("inputmode"))->toBe("numeric")
    expect(field->attrOr("autocomplete"))->toBe("off")
  })
})
