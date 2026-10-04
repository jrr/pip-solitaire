// The toast's words and which of them stay up, which is all a player watching the corner
// has to go on.
open Vitest
open TestDom

describe("HintToast", () => {
  test("stays up while it is looking, and fades once it has an answer", () => {
    expect(HintToast.fades(HintToast.Thinking))->toBe(false)
    expect(HintToast.fades(HintToast.Found({moves: 3})))->toBe(true)
    expect(HintToast.fades(HintToast.Unwinnable))->toBe(true)
  })

  test("counts the moves left, one or many", () => {
    expect(HintToast.text(HintToast.Found({moves: 1})))->toBe("Solution found · 1 move to go")
    expect(HintToast.text(HintToast.Found({moves: 42})))->toBe("Solution found · 42 moves to go")
  })

  test("is a status, so a screen reader hears it without it taking focus", () => {
    let toast = Html.create(HintToast.make({news: HintToast.Unwinnable, leaving: false}))
    expect(toast->attr("role"))->toBe(Some("status"))
    expect(toast->attr("class"))->toBe(Some("hint-toast"))
    let leaving = Html.create(HintToast.make({news: HintToast.Unwinnable, leaving: true}))
    expect(leaving->attr("class"))->toBe(Some("hint-toast hint-toast--leaving"))
  })
})
