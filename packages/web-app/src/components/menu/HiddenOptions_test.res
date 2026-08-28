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

  test("ten more taps hide them again", () => {
    // The gesture is a toggle: hiding is just revealing again, same count.
    let revealed = tapTimes(HiddenOptions.tapsToReveal)
    let state = ref(revealed)
    for _ in 1 to HiddenOptions.tapsToReveal - 1 {
      state := HiddenOptions.tap(state.contents)
    }
    expect(state.contents.revealed)->toBe(true) // nine taps in, still showing
    expect(HiddenOptions.tap(state.contents).revealed)->toBe(false)
  })

  test("and ten after that reveal them once more", () => {
    let state = ref(HiddenOptions.initial(~revealed=false))
    for _ in 1 to HiddenOptions.tapsToReveal * 3 {
      state := HiddenOptions.tap(state.contents)
    }
    // Three runs: reveal, hide, reveal.
    expect(state.contents.revealed)->toBe(true)
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

  test("a reset never flips the reveal itself", () => {
    // Leaving Settings abandons the run in progress; it doesn't hide what's showing
    // (nor reveal what isn't).
    let revealed = tapTimes(HiddenOptions.tapsToReveal)
    expect(HiddenOptions.reset(revealed).revealed)->toBe(true)
    expect(HiddenOptions.reset(tapTimes(3)).revealed)->toBe(false)
  })

  test("a part-finished run can't be finished into a re-hide", () => {
    // Nine taps past a reveal, then out of Settings and back: the options stay put
    // rather than vanishing on the next stray tap.
    let state = ref(tapTimes(HiddenOptions.tapsToReveal))
    for _ in 1 to HiddenOptions.tapsToReveal - 1 {
      state := HiddenOptions.tap(state.contents)
    }
    let abandoned = HiddenOptions.reset(state.contents)
    expect(HiddenOptions.tap(abandoned).revealed)->toBe(true)
  })

  test("only the flipping tap reports a change", () => {
    // What `Main` persists on — the other nine taps in a run must not write storage.
    let ninth = tapTimes(HiddenOptions.tapsToReveal - 1)
    let tenth = HiddenOptions.tap(ninth)
    expect(HiddenOptions.revealChanged(~before=ninth, ~after=tenth))->toBe(true)
    expect(HiddenOptions.revealChanged(~before=tenth, ~after=HiddenOptions.tap(tenth)))->toBe(false)
    // And it reports in the hiding direction too, so the flag is persisted back off.
    let ninthPastReveal = ref(tenth)
    for _ in 1 to HiddenOptions.tapsToReveal - 1 {
      ninthPastReveal := HiddenOptions.tap(ninthPastReveal.contents)
    }
    let hidden = HiddenOptions.tap(ninthPastReveal.contents)
    expect(hidden.revealed)->toBe(false)
    expect(HiddenOptions.revealChanged(~before=ninthPastReveal.contents, ~after=hidden))->toBe(true)
  })
})
