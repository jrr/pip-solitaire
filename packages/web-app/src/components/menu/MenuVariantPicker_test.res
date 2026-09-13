// The info screen's variant picker. What it offers comes from the real families, so the
// claims here are about a player's three packs rather than about three invented ones;
// what a mark looks like is `MenuVariantMark`'s, and which board is chosen by a tap is
// `Main`'s.
open Vitest
open TestDom

// A family as the picker is handed one: every variant of it, with `on` the chosen board
// and each tap logged by its game's id.
let render = (family: Game.family, ~on: Game.t, ~log=[]) =>
  Html.create(
    MenuVariantPicker.make({
      game: family.name,
      noun: GameVariant.nounFor(family),
      choices: family.variants->Array.map((v): MenuVariantPicker.choice => {
        mark: GameVariant.forVariant(v),
        selected: v.game.id == on.id,
        onChoose: () => log->Array.push(v.game.id),
      }),
    }),
  )

let marks = (picker: element) => picker->findAll(".menu-variant-picker__choice")->Array.map(text)

describe("MenuVariantPicker", () => {
  test("lays every board of the family out at once, in the family's own order", () => {
    // The whole difference from the Games list's segment, which shows one and cycles:
    // a screen about a game has room to put the choice in front of a player.
    expect(marks(render(Game.spideretteFamily, ~on=Game.spiderette)))->toEqual([
      "♠×4",
      "♠♥×2",
      "♠♥♦♣",
    ])
    expect(marks(render(Game.freecellFamily, ~on=Game.freecell)))->toEqual([
      "Standard",
      "Mini",
      "Micro",
    ])
  })

  test("lights the one the screen is about, and only that one", () => {
    let picker = render(Game.freecellFamily, ~on=Game.mini)
    expect(
      picker->findAll(".menu-variant-picker__choice")->Array.map(el => el->attrOr("aria-current")),
    )->toEqual(["<missing>", "true", "<missing>"])
    // The highlight is `.menu-row`'s own — the same green the Games list's rows wear —
    // rather than a second one this control defines.
    expect(picker->find(".menu-row--active")->Option.mapOr("", text))->toBe("Mini")
  })

  test("names each button with whose variants these are, what varies, and which one", () => {
    // Three marks in a row are three controls with no subject; the label is what a
    // screen reader has instead, and it names the *state* rather than the tap — which
    // is what makes it a control a player can come back to.
    let picker = render(Game.spideretteFamily, ~on=Game.spiderette)
    expect(
      picker->findAll(".menu-variant-picker__choice")->Array.map(el => el->attrOr("aria-label")),
    )->toEqual(["Spiderette pack: 1 suit", "Spiderette pack: 2 suits", "Spiderette pack: 4 suits"])
  })

  test("reports the board a tap chose, including the one already chosen", () => {
    // The chosen board is not inert: the screen is already showing it, so a tap on it
    // asks for what is already there — and a control that swallowed the tap would be
    // the only one here that does nothing.
    let log = []
    let picker = render(Game.spideretteFamily, ~on=Game.spiderette, ~log)
    picker->findAll(".menu-variant-picker__choice")->Array.forEach(click)
    expect(log)->toEqual(["spiderette1", "spiderette", "spiderette4"])
  })

  test("is buttons, so a tap is a tap and not a form submission", () => {
    expect(
      render(Game.freecellFamily, ~on=Game.micro)
      ->findAll(".menu-variant-picker__choice")
      ->Array.map(el => (el->tag, el->attrOr("type"))),
    )->toEqual([("BUTTON", "button"), ("BUTTON", "button"), ("BUTTON", "button")])
  })
})
