# Save and share

A game in progress can be written to `localStorage` and resumed, or turned into a
link and sent to someone. Both use the same encoding, so this is one pipeline with
two destinations:

```
GameState history ──► SaveState JSON ──► deflate-raw ──► base64url ──┬─► #g=… link
                                    └──────────────────────────────────► localStorage
                                        (uncompressed, straight to storage)
```

Four modules, one per segment:

| | |
|---|---|
| `core/src/SaveState.res` | the JSON format — encode and decode |
| `web-app/src/platform/SavedGame.res` | `localStorage` keys, reads and writes |
| `web-app/src/platform/Compression.res` | `deflate-raw` + base64url, both ways |
| `web-app/src/platform/ShareLink.res` | building links, and handing them to the player |

## What a save is

The undo/redo history — not just the current board — plus the numbers beside it:

```json
{"v":1,"game":"freecell",
 "past":[S,…],"present":S,"future":[S,…],
 "stats":{"moves":n,"undos":n,"autoplays":n},
 "timing":{"dealtAt":ms,"wonAt":ms}}
```

A state `S` is `{"piles":[[C,…],…],"loose":[C,…]}`. A card `C` is two characters,
rank then suit: `TS`, `AH`. Small, legible in a stored blob, trivially reversible.

Saving the whole history means a restored game has the Undo stack the player left,
not just the position.

## The version stays at 1

`v` is a compatibility gate: `decode` rejects any other version, and the caller
treats that as "no saved game" and deals fresh.

Four fields have been added since v1 shipped — `stats`, `autoplays`, `timing`,
`game` — and **none of them bumped it**. Each is optional in both directions:

- a blob written before the field existed decodes here, with a sensible stand-in
- a blob written *with* it decodes in an older build, which ignores what it doesn't
  know

Absence and nonsense are different things. A missing field is a supported shape. A
field that's *present* and malformed fails the whole save — that isn't a blob we
wrote, and half-reading a stranger's JSON is how a broken board gets built.

Bumping `v` costs every saved game on every device and every link already sitting in
someone's chat history. Reserve it for a change that genuinely can't be read both
ways. Adding a field is not one.

What each absent field means:

| absent | reads as |
|---|---|
| `stats` | tally inferred from the history (`moves` = its length, `undos` = 0) |
| `autoplays` | 0 — a game played before autoplay existed didn't use it |
| `timing` | a game nobody clocked (`Timing.unknown`) |
| `wonAt` alone | a game still being played |
| `game` | "this save doesn't say" — the *reader* resolves it to `Game.default` |

That last one is deliberately not filled in by `SaveState`. Which game a nameless
save belongs to is a question about the app's list of games; `SaveState` is the wire
format, so it reports absence and lets `ShareLink.savedFrom` answer.

A save also has to *fit* the board it's read onto: `SaveState.fits` checks the pile
count of every state, past and future included, so a save that fits at the present
can't come apart one Undo later.

## Two kinds of link

| | carries | rides in | why |
|---|---|---|---|
| `#g=<blob>` | the whole position, history and all | the fragment | recipient picks up where the sender left off |
|  `?game=…&seed=7` | which board to deal | the query | both players start level |

The deal link is the legible one. It survives being read off one screen and typed
into another, which is half the point of a deal number — so `?game=` is omitted when
the game is `Game.default`, and `?seed=7` stays short.

It is also the one that outlives the build that made it. A number typed into next
year's app has to deal the same board, which freezes the shuffle behind it; the
banner in `core/src/Cards.res` says exactly what that freezes and how to change the
shuffle without breaking a link.

The win overlay's Share button is a *deal* link with a message wrapped around it
(`victoryMessage`), never a `#g=` link. Sharing the position from a won board would
ship the solution.

## Why the fragment

`#g=` rather than `?g=`, for two reasons that both point the same way:

- **A fragment is never sent to the server.** That sidesteps the ~8 KB
  request-line limit that Apache, nginx and CloudFront impose on the path and
  query — the only hard length limit anywhere in this pipeline. Browsers accept far
  longer URLs than we'd ever generate.
- **It keeps the player's board out of server logs, `Referer` headers and
  analytics.** The state is the client's business.

The cost: link-preview crawlers can't see the fragment, so a shared link can never
render a picture of the position. We don't offer that anyway.

It also keeps `#g=` cleanly apart from the `?state=`/`?seed=` parameters `AppUrl`
already parses. Different halves of the URL, no precedence to negotiate.

## Why `deflate-raw` and base64url

The compressor is the browser's own Compression Streams API — nothing in the bundle,
nothing to keep current. A 200-move FreeCell game is ~59 KB of JSON and comes out
around 1,800 URL-safe characters.

- **`deflate-raw`, not `gzip`.** Same DEFLATE stream, less framing. Nobody outside
  this app reads these bytes, so gzip's 18-byte header and footer are pure
  overhead — about 24 characters once base64'd. Nothing on a long game; a tenth of
  the payload on a fresh deal.
- **base64url, not base64.** `+/` become `-_` and the `=` padding is dropped
  (re-derived on the way back). RFC 4648 §5. The blob then never needs
  percent-encoding, which would re-inflate it up to 3× and undo the point.

Both directions are async — the API is stream-shaped and there is no synchronous
alternative.

## Storage

One saved game per *game type*, keyed by game id:

| key | holds |
|---|---|
| `pip.savedGame.<gameId>` | the `SaveState` JSON, uncompressed |
| `pip.savedDeal.<gameId>` | the deal number, as a bare integer |

The deal number lives *beside* the history rather than in it. The format carries
positions, which is all replaying needs; the seed isn't part of the game state. But
a resumed board can't work its own deal number out — the positions are restored, the
deal that produced them is gone — so without this key the Share button would go dark
on the most ordinary case there is.

A shared game that arrives takes over storage: it becomes the saved game and play
continues saving as usual, exactly as if it had been dealt here. Its deal number is
*cleared* (`clearSeed`), because a shared position was never dealt from a number on
this device and the previous game's seed must not be read as its own.

## Nothing here can take the board down

Every failure in this pipeline lands on the same answer: **ignore it and deal a
playable game.**

- `localStorage` throws (Safari private mode, sandboxed frame, disabled, full) — a
  failed read is "no saved game", a failed write is swallowed
- the blob isn't valid JSON, is the wrong version, or has a card that isn't a card
- the paste was truncated, or the bytes aren't DEFLATE, or don't inflate to UTF-8
- the browser has no Compression Streams API
- the link names a game this build doesn't have, or carries piles that don't fit it

None of it is load-bearing enough to justify an error screen. A bad link opens a
playable board; a device that can't persist just always deals fresh.

## Before you change the format

1. Can the new field be optional in both directions? If yes, add it and leave `v`
   at 1. If no, you're proposing to drop every save and every link in existence —
   say so out loud.
2. Decide what *absence* means, and make sure it's the truthful reading rather than
   a convenient default.
3. Reject present-but-malformed. Don't guess.
4. `SaveState` is pure and unit-tested in `core`. Test the new field's absent,
   present, and malformed cases there.
