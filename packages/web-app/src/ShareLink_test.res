// The share link end to end (`ShareLink`): a board's undo/redo history becomes a
// URL, and that URL's blob becomes the same history again. The interesting property
// is that nothing is lost in the middle — the recipient gets the *whole* stack, not
// just the position — since that's what "share game state" promises.
//
// The delivery half (`deliver`, the share-sheet/clipboard fork) isn't covered here:
// it's a thin wrapper over two platform APIs that jsdom doesn't implement, so a test
// would only be asserting against a stub of our own making.

open Vitest

describe("ShareLink", () => {
  let game = Game.freecell
  // A history with real depth, so a link that quietly dropped the undo stack — or
  // kept only the present state — would fail rather than pass by looking similar.
  let history =
    History.make(GameState.initial(game))
    ->History.record({...GameState.initial(game), loose: [{suit: Spades, rank: Ace}]})
    ->History.record({
      ...GameState.initial(game),
      loose: [{suit: Spades, rank: Ace}, {suit: Hearts, rank: King}],
    })

  testAsync("a link's blob restores the whole history", async () => {
    let url = (await ShareLink.urlFor(history))->Option.getExn
    let blob = url->String.split("#" ++ ShareLink.fragmentKey ++ "=")->Array.getUnsafe(1)
    expect(await ShareLink.historyFrom(blob))->toEqual(Some(history))
  })

  testAsync("the state rides in the fragment, not the query", async () => {
    // The reason there's no length ceiling to design around: a fragment never
    // reaches the server, so none of the ~8 KB request-line limits apply to it.
    let url = (await ShareLink.urlFor(history))->Option.getExn
    expect(url->String.includes("#" ++ ShareLink.fragmentKey ++ "="))->toBe(true)
    expect(url->String.includes("?"))->toBe(false)
  })

  testAsync("a corrupt blob restores nothing", async () => {
    expect(await ShareLink.historyFrom("not-a-real-blob"))->toEqual(None)
  })

  testAsync("a blob carrying valid but non-SaveState JSON restores nothing", async () => {
    // `SaveState.decode`'s version/shape rejection has to survive the trip through
    // the codec: a link that decompresses cleanly can still be one this build can't
    // read, and that must read as "no game" rather than a half-built board.
    let blob = (await Compression.compress(`{"v":99,"past":[],"present":null}`))->Option.getExn
    expect(await ShareLink.historyFrom(blob))->toEqual(None)
  })
})
