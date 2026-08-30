// The share link end to end (`ShareLink`): a board's saved game becomes a URL, and
// that URL's blob becomes the same game again. The interesting property is that
// nothing is lost in the middle — the recipient gets the *whole* stack, not just the
// position, and the move and undo counts with it — since that's what
// "share game state" promises.
//
// That includes *which game* the stack is a stack of: without it the blob lands on
// whichever board happens to be mounted at the far end. The resolving happens here
// rather than in `core`, so it's pinned here too.
//
// The module's other link — `urlForDeal`, which shares a *deal number* rather than a
// position — has no codec to round-trip, so it is pinned on the shape of the URL it
// builds instead. `browser-tests/share-deal.spec.mjs` closes the loop on both by
// opening the link for real.
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
  let saved: SaveState.t = {
    history,
    stats: {moves: 5, undos: 2, autoplays: 0},
    timing: Timing.dealt(~at=1_700_000_000_000.),
    gameId: Some(game.id),
  }

  // The blob straight out of a link, which is what `savedFrom` is handed.
  let blobOf = async (s: SaveState.t) => {
    let url = (await ShareLink.urlFor(s))->Option.getOrThrow
    url->String.split("#" ++ ShareLink.fragmentKey ++ "=")->Array.getUnsafe(1)
  }

  testAsync("a link's blob restores the whole game", async () => {
    let blob = await blobOf(saved)
    switch await ShareLink.savedFrom(blob) {
    | Some(restored) => expect(restored.saved)->toEqual(saved)
    | None => expect("restored")->toBe("but got None")
    }
  })

  testAsync("the move and undo counts ride along in the link", async () => {
    // The counts live outside the game state, so nothing about a position implies
    // them: they make it into a share link only because they're in the save envelope
    // the link carries.
    let blob = await blobOf(saved)
    switch await ShareLink.savedFrom(blob) {
    | Some(restored) =>
      expect(restored.saved.stats)->toEqual({Stats.moves: 5, undos: 2, autoplays: 0})
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
    // The other share, and deliberately the opposite trade: no payload, so no
    // compression, no fragment, and a link a player can read off one screen and type
    // into another. The key is the one `AppUrl` parses, which is the round trip the
    // browser suite then makes for real.
    let url = ShareLink.urlForDeal(~game, ~seed=24680)
    expect(url->String.includes("?" ++ ShareLink.dealKey ++ "=24680"))->toBe(true)
    expect(url->String.includes("#"))->toBe(false)
  })

  test("a deal link drops the query that got this board on screen", () => {
    // Whatever `?state=`/`?seed=` opened this page, the deal number now says it in
    // full — so the link is the bare page plus the number, and can't carry a scenario
    // or a stale seed along with it. (`?scene=` is the exception, below: it says which
    // game the number is a deal of, which the number can't say for itself.)
    let url = ShareLink.urlForDeal(~game, ~seed=7)
    expect(url->String.split("?")->Array.length)->toBe(2)
    expect(url->String.includes("state="))->toBe(false)
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

  testAsync("a link written before the tally existed still opens", async () => {
    // The counts were added to the save envelope without moving its version, so a
    // link already sitting in somebody's chat has to keep working. It comes back as a
    // real game whose tally was inferred rather than as "couldn't read that".
    let legacy =
      SaveState.encode(saved)
      ->String.replaceRegExp(/,"stats":\{[^}]*\}/, "")
      ->String.replaceRegExp(/,"timing":\{[^}]*\}/, "")
    let blob = (await Compression.compress(legacy))->Option.getOrThrow
    switch await ShareLink.savedFrom(blob) {
    | Some(restored) => expect(restored.saved.history)->toEqual(history)
    | None => expect("restored")->toBe("but got None")
    }
  })
})

// Which *game* a shared blob is a game of. The link carried the cards and not
// the board they belong to, so it decoded onto whatever scene happened to be mounted —
// which was only ever safe because there was one game to mount. Now the blob names its
// board, and this is the end that resolves the name: against `Game.all`, before anything
// is handed to a scene.
describe("ShareLink.savedFrom names the game", () => {
  let blobFor = async (s: SaveState.t) =>
    (await Compression.compress(SaveState.encode(s)))->Option.getOrThrow

  let saveOf = (game: Game.t): SaveState.t =>
    SaveState.ofHistory(History.make(GameState.initial(game)))

  testAsync("a link shared from another game comes back as that game", async () => {
    let blob = await blobFor({...saveOf(Game.mini), gameId: Some(Game.mini.id)})
    switch await ShareLink.savedFrom(blob) {
    | Some({game}) => expect(game.id)->toBe("mini")
    | None => expect("restored")->toBe("but got None")
    }
  })

  testAsync("a link naming no game at all is the default game's", async () => {
    // What every link written before the field existed is: FreeCell was the only game
    // that could have written one, so this is a reading rather than a fallback — and it
    // is what keeps a link already sitting in somebody's chat working.
    let blob = await blobFor(saveOf(Game.default))
    switch await ShareLink.savedFrom(blob) {
    | Some({game}) => expect(game.id)->toBe(Game.default.id)
    | None => expect("restored")->toBe("but got None")
    }
  })

  testAsync("a link naming a game this build doesn't have restores nothing", async () => {
    // The same answer a truncated paste gets, for the same reason: there's no board to
    // open this onto, so the caller ignores the link and deals normally rather than
    // guessing at which game was meant.
    let blob = await blobFor({...saveOf(Game.freecell), gameId: Some("solitaire-9000")})
    expect(await ShareLink.savedFrom(blob))->toEqual(None)
  })

  testAsync("a link whose board doesn't fit the game it names restores nothing", async () => {
    // A blob can name a board and not be one — hand-edited, or written by a build where
    // that game had another shape. Ten piles of cards laid onto a sixteen-pile board is
    // precisely the misread this field exists to stop, so naming the game is checked
    // against the cards rather than taken on trust.
    let blob = await blobFor({...saveOf(Game.mini), gameId: Some(Game.freecell.id)})
    expect(await ShareLink.savedFrom(blob))->toEqual(None)
  })
})

// Which *game* a deal number is a deal of. A link carrying only the number leaves the
// receiving end to read it as FreeCell by construction, which makes a deal of any second
// game unshareable. What's pinned here is the shape `urlForDeal` writes: the game named
// in `?game=`, and left out for the default one.
describe("ShareLink.urlForDeal names the game", () => {
  // A second seeded game, stood up here because `Game.all` has only FreeCell in the
  // web-app's own scene list. Everything `urlForDeal` reads of a game is its
  // `id`, so a FreeCell board under another name is a faithful stand-in for the day a
  // real second game arrives — and it's this test, not that day, that has to catch a
  // link which quietly means FreeCell.
  let mini = {...Game.freecell, id: "mini", name: "Mini"}

  test("a deal of another game names it with `?game=`", () => {
    let url = ShareLink.urlForDeal(~game=mini, ~seed=7)
    expect(url->String.endsWith("?game=mini&seed=7"))->toBe(true)
  })

  test("…and the default game leaves it out, for the link to stay legible", () => {
    // `?seed=7` is short enough to be read off one screen and typed into another,
    // which the module's own note calls half the point of a deal number.
    // `?game=freecell&seed=7` is not, and would say twice what the bare form already
    // says once — `Game.default` is where "a number with no game named" resolves.
    let url = ShareLink.urlForDeal(~game=Game.default, ~seed=7)
    expect(url->String.endsWith("?seed=7"))->toBe(true)
    expect(url->String.includes(ShareLink.gameKey))->toBe(false)
  })

  test("the default game's link is the bare page plus `?seed=`, and nothing else", () => {
    // Stated from the sending end, in full rather than by `endsWith`: no game, no
    // leftovers from the query that opened the page, no fragment. The receiving half —
    // a bare `?seed=` landing on FreeCell — can't be asked here, since it's a page
    // load; `browser-tests/share-deal.spec.mjs` makes it.
    let bare = seed => ShareLink.origin ++ ShareLink.pathname ++ "?seed=" ++ Int.toString(seed)
    expect(ShareLink.urlForDeal(~game=Game.freecell, ~seed=24680))->toBe(bare(24680))
  })

  test("the parameter it writes is the one `AppUrl` reads, and it says `game`", () => {
    // The two ends agree by construction — one spelling, in this module — so a link
    // that named its game in a parameter nothing parses isn't expressible. The literal
    // is pinned as well as the round trip: `AppUrl` documents `?game=` as the deal
    // link's half, and a rename here that left that prose behind would be silent.
    expect(ShareLink.gameKey)->toBe("game")
    expect(
      ShareLink.urlForDeal(~game=mini, ~seed=7)->String.includes(ShareLink.gameKey ++ "="),
    )->toBe(true)
  })
})

// The victory message: what the win overlay hands over when a player wins.
// It's a *string* the recipient reads, so what's pinned here is what it says — the
// deal number they need to play the same board, and what the win cost in moves and
// undos — and, just as load-bearing, what it doesn't say: no URL of its
// own, because `deliver` adds the link on whichever route it takes and a message
// that composed one too would deliver it twice.
describe("ShareLink.victoryMessage", () => {
  let game = Game.freecell

  test("names the deal and how many moves it took", () => {
    let message = ShareLink.victoryMessage(~game, ~seed=847213, ~moves=94, ~undos=0)
    expect(message->String.includes("847213"))->toBe(true)
    expect(message->String.includes("94 moves"))->toBe(true)
    // The suits lead the message — the thing that makes it recognisable in a chat.
    expect(message->String.startsWith("♣️♥️♠️♦️"))->toBe(true)
  })

  test("counts a one-move win in the singular", () => {
    let message = ShareLink.victoryMessage(~game, ~seed=1, ~moves=1, ~undos=0)
    expect(message->String.includes("1 move"))->toBe(true)
    expect(message->String.includes("moves"))->toBe(false)
  })

  // The undo count is the message's one conditional clause: a clean run says
  // nothing about undos, so the clause being there at all is part of what's reported.
  test("names the undos when there were any", () => {
    let message = ShareLink.victoryMessage(~game, ~seed=847213, ~moves=94, ~undos=3)
    expect(message->String.includes("94 moves"))->toBe(true)
    expect(message->String.includes("3 undos"))->toBe(true)
  })

  test("says nothing about undos when there weren't any", () => {
    let message = ShareLink.victoryMessage(~game, ~seed=847213, ~moves=94, ~undos=0)
    expect(message->String.includes("undo"))->toBe(false)
  })

  test("counts a single undo in the singular too", () => {
    let message = ShareLink.victoryMessage(~game, ~seed=1, ~moves=40, ~undos=1)
    expect(message->String.includes("1 undo"))->toBe(true)
    expect(message->String.includes("undos"))->toBe(false)
  })

  test("carries no link of its own — `deliver` owns the URL", () => {
    let message = ShareLink.victoryMessage(~game, ~seed=847213, ~moves=94, ~undos=0)
    expect(message->String.includes("http"))->toBe(false)
    expect(message->String.includes(ShareLink.dealKey ++ "="))->toBe(false)
  })

  test("shares the deal, never the position", () => {
    // The one thing this share must never do is hand over a solved board, so the
    // number in the message has to be the one `urlForDeal` will build a link from —
    // the deal, which both players can start level on.
    expect(
      ShareLink.urlForDeal(~game, ~seed=847213)->String.endsWith(
        "?" ++ ShareLink.dealKey ++ "=847213",
      ),
    )->toBe(true)
  })

  // The boast names the game it was won on, read off the game rather than
  // spelled into the string. "Pip FreeCell #264" is what it has always said and what it
  // still says — the wording didn't change, only where the word comes from.
  test("names the game the win happened on", () => {
    let mini = {...Game.freecell, id: "mini", name: "Mini"}
    expect(
      ShareLink.victoryMessage(~game=mini, ~seed=7, ~moves=94, ~undos=0)->String.startsWith(
        "♣️♥️♠️♦️ Pip Mini #7",
      ),
    )->toBe(true)
    expect(
      ShareLink.victoryMessage(~game, ~seed=7, ~moves=94, ~undos=0)->String.startsWith(
        "♣️♥️♠️♦️ Pip FreeCell #7",
      ),
    )->toBe(true)
  })
})
