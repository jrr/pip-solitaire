open Vitest
open Card

// Serializing a game's progress (#177): the round-trip must be lossless — a saved
// game decodes back to the *exact* board, positions, undo/redo stack and play tally
// (#289) — and anything untrustworthy (corrupt, foreign, or an older format) must
// decode to `None` so the app deals fresh rather than showing a misread board.
describe("SaveState", () => {
  // A small, hand-built history over FreeCell states: an opening deal, a move to a
  // free cell, and one step undone away — so `past`, `present` and `future` are all
  // non-empty and the round-trip has something to preserve in each.
  let opening = GameState.initial(Game.freecell)
  let moved = {...opening, loose: [{suit: Spades, rank: Ace}]}
  let latest = {...opening, loose: [{suit: Spades, rank: Ace}, {suit: Hearts, rank: King}]}
  let history = History.make(opening)->History.record(moved)->History.record(latest)->History.undo
  // …and the game around it: two moves played and one undone, which is a tally no
  // fallback could invent (`History.steps` of this history is 1, not 2) — so a save
  // that dropped the counts would fail here rather than pass by looking plausible.
  let saved: SaveState.t = {history, stats: {moves: 2, undos: 1, autoplays: 1}}

  test("a card round-trips through its two-character code", () => {
    Cards.all->Array.forEach(
      card => expect(SaveState.decodeCard(SaveState.encodeCard(card)))->toEqual(Some(card)),
    )
  })

  test("encode then decode restores the whole saved game exactly", () => {
    switch SaveState.decode(SaveState.encode(saved)) {
    | Some(restored) => expect(restored)->toEqual(saved)
    | None => expect("decoded")->toBe("but got None")
    }
  })

  test("the present, past and future all survive the round-trip", () => {
    switch SaveState.decode(SaveState.encode(saved)) {
    | Some(restored) =>
      expect(History.present(restored.history))->toEqual(moved) // undone from `latest` back to `moved`
      expect(History.canUndo(restored.history))->toBe(true) // `opening` is still behind us
      expect(History.canRedo(restored.history))->toBe(true) // `latest` is redoable
    | None => expect("decoded")->toBe("but got None")
    }
  })

  test("the move, undo and autoplay counts survive the round-trip (#289, #291)", () => {
    switch SaveState.decode(SaveState.encode(saved)) {
    | Some(restored) => expect(restored.stats)->toEqual({Stats.moves: 2, undos: 1, autoplays: 1})
    | None => expect("decoded")->toBe("but got None")
    }
  })

  // `autoplays` joined the tally after the tally itself had shipped (#291), so a save
  // written between the two has `stats` but no `autoplays` — and has to keep working
  // for the same reason a pre-tally save does. A game saved before the solver could be
  // reached for cannot have used it, so none is the truthful reading, not a guess.
  test("a tally written before autoplay existed reads as never autoplayed", () => {
    let earlier = SaveState.encode(saved)->String.replaceRegExp(/,"autoplays":\d+/, "")
    expect(earlier->String.includes("autoplays"))->toBe(false) // the fixture really is older
    switch SaveState.decode(earlier) {
    | Some(restored) => expect(restored.stats)->toEqual({Stats.moves: 2, undos: 1, autoplays: 0})
    | None => expect("decoded")->toBe("but got None")
    }
  })

  test("a fresh (no moves) game round-trips too", () => {
    let fresh: SaveState.t = {history: History.make(opening), stats: Stats.zero}
    switch SaveState.decode(SaveState.encode(fresh)) {
    | Some(restored) =>
      expect(restored)->toEqual(fresh)
      expect(History.canUndo(restored.history))->toBe(false)
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

  // The tally arrived after the format did (#289), and the version deliberately
  // didn't move for it — so a blob written by an older build has to keep working,
  // both out of `localStorage` and out of a share link somebody already sent.
  describe("a save written before the tally existed", () => {
    // Exactly what a pre-#289 `encode` produced: two states behind the present, no
    // `stats` key anywhere.
    let legacy = SaveState.encode(saved)->String.replaceRegExp(/,"stats":\{[^}]*\}/, "")

    test(
      "still decodes to a real game",
      () => {
        expect(legacy->String.includes("stats"))->toBe(false) // the fixture really is legacy
        switch SaveState.decode(legacy) {
        | Some(restored) => expect(restored.history)->toEqual(history)
        | None => expect("decoded")->toBe("but got None")
        }
      },
    )

    test(
      "infers its move count from the line behind the present",
      () => {
        // The one thing such a save can still say about how it got here — and the number
        // the victory share reported before the tally existed. Undos left no trace, so
        // they read as none rather than as a guess.
        switch SaveState.decode(legacy) {
        | Some(restored) =>
          expect(restored.stats)->toEqual({
            Stats.moves: History.steps(history),
            undos: 0,
            autoplays: 0,
          })
        | None => expect("decoded")->toBe("but got None")
        }
      },
    )
  })

  test("a present-but-malformed tally is rejected like any other bad field", () => {
    // Absent `stats` is a shape we support (above); `stats` of the wrong shape means
    // this isn't a blob we wrote, and half-reading a stranger's JSON is how a broken
    // board gets built.
    let states = `"past":[],"present":{"piles":[],"loose":[]},"future":[]`
    expect(SaveState.decode(`{"v":1,${states},"stats":{"moves":"lots","undos":0}}`))->toEqual(None)
    expect(SaveState.decode(`{"v":1,${states},"stats":{"moves":3}}`))->toEqual(None)
    expect(SaveState.decode(`{"v":1,${states},"stats":7}`))->toEqual(None)
    expect(SaveState.decode(`{"v":1,${states},"stats":{"moves":-1,"undos":0}}`))->toEqual(None)
    // …including the field that's allowed to be *absent*: missing is an older save,
    // nonsense is a stranger's JSON, and the two aren't the same thing.
    expect(
      SaveState.decode(`{"v":1,${states},"stats":{"moves":1,"undos":0,"autoplays":"lots"}}`),
    )->toEqual(None)
  })
})
