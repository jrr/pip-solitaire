// The variant mark, drawn from the real families rather than from fixtures: what a mark
// *is* for a given board is `GameVariant`'s claim and tested there, and what is left
// here is which elements it becomes — which is the half two controls share
// (`MenuGameRow`, `MenuVariantPicker`) and so the half neither of them may re-spell.
open Vitest
open TestDom

// In a box of its own, because the mark is a fragment and `Html.create` hands a single
// node back as itself: a word mark is one span, and a query for that span would be a
// query *inside* it.
let render = (game: Game.t) =>
  Html.create(
    <div>
      <MenuVariantMark mark={Game.variantOf(game)->Option.getOrThrow->GameVariant.forVariant} />
    </div>,
  )

describe("MenuVariantMark", () => {
  test("draws a pack as pips, with a multiplier only where there is more than one", () => {
    let pack = render(Game.spiderette)
    expect(pack->textIn(".menu-variant-mark__suits"))->toBe("♠♥")
    expect(pack->textIn(".menu-variant-mark__copies"))->toBe("×2")
    // The standard pack, once: four suits and nothing after them.
    let standard = render(Game.spiderette4)
    expect(standard->textIn(".menu-variant-mark__suits"))->toBe("♠♥♦♣")
    expect(standard->findAll(".menu-variant-mark__copies")->Array.length)->toBe(0)
  })

  test("keeps the pips and the multiplier in spans of their own", () => {
    // They are set differently — the pips in the app's own suit face, the "×2" a size
    // down and lighter — so one span carrying both would have to choose between them.
    // The space a reader sees between them is the stylesheet's, so the text runs
    // together here.
    expect(render(Game.spiderette1)->text)->toBe("♠×4")
    expect(render(Game.spiderette1)->findAll("span")->Array.length)->toBe(2)
  })

  test("draws a size as the word itself, with no pips in it at all", () => {
    let size = render(Game.mini)
    expect(size->textIn(".menu-variant-mark__word"))->toBe("Mini")
    expect(size->findAll(".menu-variant-mark__suits")->Array.length)->toBe(0)
  })
})
