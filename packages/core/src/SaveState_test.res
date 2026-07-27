open Vitest
open Card

// Serializing a game's progress (#177): the round-trip must be lossless — a saved
// history decodes back to the *exact* board, positions and undo/redo stack — and
// anything untrustworthy (corrupt, foreign, or an older format) must decode to
// `None` so the app deals fresh rather than showing a misread board.
describe("SaveState", () => {
  // A small, hand-built history over FreeCell states: an opening deal, a move to a
  // free cell, and one step undone away — so `past`, `present` and `future` are all
  // non-empty and the round-trip has something to preserve in each.
  let opening = GameState.initial(Game.freecell)
  let moved = {...opening, loose: [{suit: Spades, rank: Ace}]}
  let latest = {...opening, loose: [{suit: Spades, rank: Ace}, {suit: Hearts, rank: King}]}
  let history = History.make(opening)->History.record(moved)->History.record(latest)->History.undo

  test("a card round-trips through its two-character code", () => {
    Cards.all->Array.forEach(
      card => expect(SaveState.decodeCard(SaveState.encodeCard(card)))->toEqual(Some(card)),
    )
  })

  test("encode then decode restores the whole history exactly", () => {
    switch SaveState.decode(SaveState.encode(history)) {
    | Some(restored) => expect(restored)->toEqual(history)
    | None => expect("decoded")->toBe("but got None")
    }
  })

  test("the present, past and future all survive the round-trip", () => {
    switch SaveState.decode(SaveState.encode(history)) {
    | Some(restored) =>
      expect(History.present(restored))->toEqual(moved) // undone from `latest` back to `moved`
      expect(History.canUndo(restored))->toBe(true) // `opening` is still behind us
      expect(History.canRedo(restored))->toBe(true) // `latest` is redoable
    | None => expect("decoded")->toBe("but got None")
    }
  })

  test("a fresh (no moves) history round-trips too", () => {
    let fresh = History.make(opening)
    switch SaveState.decode(SaveState.encode(fresh)) {
    | Some(restored) =>
      expect(restored)->toEqual(fresh)
      expect(History.canUndo(restored))->toBe(false)
    | None => expect("decoded")->toBe("but got None")
    }
  })

  test("non-JSON garbage decodes to None", () => {
    expect(SaveState.decode("not json at all {"))->toEqual(None)
  })

  test("an empty string decodes to None", () => {
    expect(SaveState.decode(""))->toEqual(None)
  })

  test("a wrong (older/newer) format version is ignored", () => {
    // Valid JSON of the right *shape* but a version this build doesn't understand.
    let stale = `{"v":999,"past":[],"present":{"piles":[],"loose":[]},"future":[]}`
    expect(SaveState.decode(stale))->toEqual(None)
  })

  test("a structurally valid blob with a bogus card is rejected whole", () => {
    // "ZZ" is not a real card code, so the entire state — and thus the save — fails
    // to decode rather than yielding a partial board.
    let bad = `{"v":1,"past":[],"present":{"piles":[["ZZ"]],"loose":[]},"future":[]}`
    expect(SaveState.decode(bad))->toEqual(None)
  })

  test("valid JSON of the wrong shape decodes to None", () => {
    expect(SaveState.decode(`{"v":1,"present":42}`))->toEqual(None)
  })
})
