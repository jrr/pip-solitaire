// The share link end to end (`ShareLink`): a board's saved game becomes a URL, and
// that URL's blob becomes the same game again. The interesting property is that
// nothing is lost in the middle — the recipient gets the *whole* stack, not just the
// position, and (since #289) the move and undo counts with it — since that's what
// "share game state" promises.
//
// The module's other link — `urlForDeal` (#98), which shares a *deal number* rather
// than a position — is pinned here too, on the shape of the URL it builds. It has no
// codec to round-trip; what it promises is that the number lands in the query
// parameter the app parses, which `browser-tests/share-deal.spec.mjs` then closes the
// loop on by opening the link for real.
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
  // A tally that the history alone couldn't produce (five moves and two undos behind
  // a two-step line), so a link that dropped the counts — or re-derived them from the
  // stack — fails rather than passing by looking close enough.
  let saved: SaveState.t = {history, stats: {moves: 5, undos: 2}}

  testAsync("a link's blob restores the whole game", async () => {
    let url = (await ShareLink.urlFor(saved))->Option.getOrThrow
    let blob = url->String.split("#" ++ ShareLink.fragmentKey ++ "=")->Array.getUnsafe(1)
    expect(await ShareLink.savedFrom(blob))->toEqual(Some(saved))
  })

  testAsync("the move and undo counts ride along in the link (#289)", async () => {
    // The counts live outside the game state, so nothing about a position implies
    // them: they make it into a share link only because they're in the save envelope
    // the link carries.
    let url = (await ShareLink.urlFor(saved))->Option.getOrThrow
    let blob = url->String.split("#" ++ ShareLink.fragmentKey ++ "=")->Array.getUnsafe(1)
    switch await ShareLink.savedFrom(blob) {
    | Some(restored) => expect(restored.stats)->toEqual({Stats.moves: 5, undos: 2})
    | None => expect("restored")->toBe("but got None")
    }
  })

  testAsync("the state rides in the fragment, not the query", async () => {
    // The reason there's no length ceiling to design around: a fragment never
    // reaches the server, so none of the ~8 KB request-line limits apply to it.
    let url = (await ShareLink.urlFor(saved))->Option.getOrThrow
    expect(url->String.includes("#" ++ ShareLink.fragmentKey ++ "="))->toBe(true)
    expect(url->String.includes("?"))->toBe(false)
  })

  test("a deal link says which board to deal, in the query and in the clear", () => {
    // The other share (#98), and deliberately the opposite trade: no payload, so no
    // compression, no fragment, and a link a player can read off one screen and type
    // into another. The key is the one `AppUrl` parses, which is the round trip the
    // browser suite then makes for real.
    let url = ShareLink.urlForDeal(24680)
    expect(url->String.includes("?" ++ ShareLink.dealKey ++ "=24680"))->toBe(true)
    expect(url->String.includes("#"))->toBe(false)
  })

  test("a deal link drops the query that got this board on screen", () => {
    // Whatever `?scene=`/`?state=`/`?seed=` opened this page, the deal number now
    // says it in full — so the link is the bare page plus the number, and can't carry
    // a scenario or a stale seed along with it.
    let url = ShareLink.urlForDeal(7)
    expect(url->String.split("?")->Array.length)->toBe(2)
  })

  testAsync("a corrupt blob restores nothing", async () => {
    expect(await ShareLink.savedFrom("not-a-real-blob"))->toEqual(None)
  })

  testAsync("a blob carrying valid but non-SaveState JSON restores nothing", async () => {
    // `SaveState.decode`'s version/shape rejection has to survive the trip through
    // the codec: a link that decompresses cleanly can still be one this build can't
    // read, and that must read as "no game" rather than a half-built board.
    let blob = (await Compression.compress(`{"v":99,"past":[],"present":null}`))->Option.getOrThrow
    expect(await ShareLink.savedFrom(blob))->toEqual(None)
  })

  testAsync("a link written before the tally existed still opens (#289)", async () => {
    // The counts were added to the save envelope without moving its version, so a
    // link already sitting in somebody's chat has to keep working. It comes back as a
    // real game whose tally was inferred rather than as "couldn't read that".
    let legacy = SaveState.encode(saved)->String.replaceRegExp(/,"stats":\{[^}]*\}/, "")
    let blob = (await Compression.compress(legacy))->Option.getOrThrow
    switch await ShareLink.savedFrom(blob) {
    | Some(restored) => expect(restored.history)->toEqual(history)
    | None => expect("restored")->toBe("but got None")
    }
  })
})

// The victory message (#264): what the win overlay hands over when a player wins.
// It's a *string* the recipient reads, so what's pinned here is what it says — the
// deal number they need to play the same board, and what the win cost in moves and
// undos (#289) — and, just as load-bearing, what it doesn't say: no URL of its
// own, because `deliver` adds the link on whichever route it takes and a message
// that composed one too would deliver it twice.
describe("ShareLink.victoryMessage (#264)", () => {
  test("names the deal and how many moves it took", () => {
    let message = ShareLink.victoryMessage(~seed=847213, ~moves=94, ~undos=0)
    expect(message->String.includes("847213"))->toBe(true)
    expect(message->String.includes("94 moves"))->toBe(true)
    // The suits lead the message — the thing that makes it recognisable in a chat.
    expect(message->String.startsWith("♣️♥️♠️♦️"))->toBe(true)
  })

  test("counts a one-move win in the singular", () => {
    let message = ShareLink.victoryMessage(~seed=1, ~moves=1, ~undos=0)
    expect(message->String.includes("1 move"))->toBe(true)
    expect(message->String.includes("moves"))->toBe(false)
  })

  // The undo count (#289) is the message's one conditional clause: a clean run says
  // nothing about undos, so the clause being there at all is part of what's reported.
  test("names the undos when there were any", () => {
    let message = ShareLink.victoryMessage(~seed=847213, ~moves=94, ~undos=3)
    expect(message->String.includes("94 moves"))->toBe(true)
    expect(message->String.includes("3 undos"))->toBe(true)
  })

  test("says nothing about undos when there weren't any", () => {
    let message = ShareLink.victoryMessage(~seed=847213, ~moves=94, ~undos=0)
    expect(message->String.includes("undo"))->toBe(false)
  })

  test("counts a single undo in the singular too", () => {
    let message = ShareLink.victoryMessage(~seed=1, ~moves=40, ~undos=1)
    expect(message->String.includes("1 undo"))->toBe(true)
    expect(message->String.includes("undos"))->toBe(false)
  })

  test("carries no link of its own — `deliver` owns the URL", () => {
    let message = ShareLink.victoryMessage(~seed=847213, ~moves=94, ~undos=0)
    expect(message->String.includes("http"))->toBe(false)
    expect(message->String.includes(ShareLink.dealKey ++ "="))->toBe(false)
  })

  test("shares the deal, never the position", () => {
    // The one thing this share must never do is hand over a solved board, so the
    // number in the message has to be the one `urlForDeal` will build a link from —
    // the deal, which both players can start level on.
    expect(
      ShareLink.urlForDeal(847213)->String.endsWith("?" ++ ShareLink.dealKey ++ "=847213"),
    )->toBe(true)
  })
})
