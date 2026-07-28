// The hidden-options tap gesture (`HiddenOptions`): counting to ten, staying
// revealed afterwards, and forgetting a part-finished run. Pure state, so it pins
// without a DOM — what it *can't* see from here is that only the Settings screen's
// title feeds taps in, which lives in `Menu`'s view and `Main`'s screen guard.

open Vitest

// Apply `n` taps in a row to a fresh locked state.
let tapTimes = n => {
  let state = ref(HiddenOptions.initial(~revealed=false))
  for _ in 1 to n {
    state := HiddenOptions.tap(state.contents)
  }
  state.contents
}

describe("Hidden options tap gesture", () => {
  test("stays hidden for the first nine taps", () => {
    // One short of the run is still locked — the whole point is that it can't be
    // stumbled into by a couple of stray taps on the title.
    expect(tapTimes(HiddenOptions.tapsToReveal - 1).revealed)->toBe(false)
    expect(tapTimes(1).revealed)->toBe(false)
    expect(tapTimes(0).revealed)->toBe(false)
  })

  test("the tenth tap reveals them", () => {
    expect(tapTimes(HiddenOptions.tapsToReveal).revealed)->toBe(true)
  })

  test("further taps are inert once revealed", () => {
    let revealed = tapTimes(HiddenOptions.tapsToReveal)
    // Physically unchanged, which is what lets the chrome loop skip the re-render.
    expect(HiddenOptions.tap(revealed) === revealed)->toBe(true)
    expect(HiddenOptions.tap(revealed).revealed)->toBe(true)
  })

  test("a device that unlocked before opens revealed", () => {
    // The persisted flag seeds the state, so the ten taps are done once per device
    // rather than once per launch.
    expect(HiddenOptions.initial(~revealed=true).revealed)->toBe(true)
  })

  test("leaving Settings abandons a part-finished run", () => {
    // Nine taps then a reset means the next tap starts from one, not ten — a
    // half-finished run doesn't lie in wait to be completed on a later visit.
    let abandoned = HiddenOptions.reset(tapTimes(HiddenOptions.tapsToReveal - 1))
    expect(abandoned.taps)->toBe(0)
    expect(HiddenOptions.tap(abandoned).revealed)->toBe(false)
  })

  test("a reset never re-hides options already revealed", () => {
    let revealed = tapTimes(HiddenOptions.tapsToReveal)
    expect(HiddenOptions.reset(revealed).revealed)->toBe(true)
  })

  test("only the revealing tap reports as such", () => {
    // What `Main` persists on. A plain `revealed` test would re-write storage on
    // every tap after the tenth.
    let ninth = tapTimes(HiddenOptions.tapsToReveal - 1)
    let tenth = HiddenOptions.tap(ninth)
    expect(HiddenOptions.justRevealed(~before=ninth, ~after=tenth))->toBe(true)
    expect(HiddenOptions.justRevealed(~before=tenth, ~after=HiddenOptions.tap(tenth)))->toBe(false)
    expect(
      HiddenOptions.justRevealed(~before=tapTimes(0), ~after=HiddenOptions.tap(tapTimes(0))),
    )->toBe(false)
  })
})
