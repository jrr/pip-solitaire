// The variant mark, drawn from the real families rather than from fixtures: what a mark
// *is* for a given board is `GameVariant`'s claim and tested there, and what is left
// here is which elements it becomes — which is the half two controls share
// (`MenuGameRow`, `MenuVariantPicker`) and so the half neither of them may re-spell.
open Vitest
open TestDom

// In a box of its own, because a mark is one span and `Html.create` hands a single node
// back as itself: a query for that span would otherwise be a query *inside* it.
let render = (game: Game.t) =>
  Html.create(
    <div>
      <MenuVariantMark mark={Game.variantOf(game)->Option.getOrThrow->GameVariant.forVariant} />
    </div>,
  )

describe("MenuVariantMark", () => {
  test("draws a pack as its suits, and nothing after them", () => {
    expect(render(Game.spiderette)->textIn(".menu-variant-mark__suits"))->toBe("♠♥")
    expect(render(Game.spiderette4)->textIn(".menu-variant-mark__suits"))->toBe("♠♥♦♣")
  })

  test("puts the whole pack in one span, the suit face being the only type it needs", () => {
    expect(render(Game.spiderette1)->text)->toBe("♠")
    expect(render(Game.spiderette1)->findAll("span")->Array.length)->toBe(1)
  })

  test("draws a size as the word itself, with no pips in it at all", () => {
    let size = render(Game.mini)
    expect(size->textIn(".menu-variant-mark__word"))->toBe("Mini")
    expect(size->findAll(".menu-variant-mark__suits")->Array.length)->toBe(0)
  })
})
