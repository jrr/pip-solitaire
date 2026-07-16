// A *game* modelled as data: a board's rules, independent of any presentation.
// This is the first step of "several supported games" (#62) — the card-stacking
// demo, described declaratively so the view can interpret it dynamically instead
// of hard-coding zones and an opening deal. A new game is a new value here, not
// new view code.
//
// What a game says:
//   - `piles` — the drop zones, each with a stacking behaviour (how a second
//     card lands on the first). The model says how many there are and how each
//     stacks; where they sit on screen is the view's business.
//   - `free`  — may a card be dropped loose on the table, outside any pile?
//     When `false`, a card released off a pile snaps back to where it came from,
//     so cards only ever rest in piles (#63).
//   - `loose` — the opening deal: specific cards resting free on the table.
//     A pile can also open holding cards (`pile.cards`), so a non-free game can
//     start with everything already stacked.
//   - `caption` — optional prose the view shows beneath the board, describing
//     how this particular game plays. `None` means no caption.
//
// The view (`TableScene`) reads all of this and lays the board out on its own
// terms — "piles hang from the top of the stage and grow downward".

open Card

// How a newcomer lands on a pile that already holds a card (#56): `Squared`
// covers the last card so the pile keeps a single card's footprint; `Fanned`
// steps off it so every card keeps a visible edge.
type stacking =
  | Squared
  | Fanned

// One drop zone: its stacking behaviour plus the cards it opens holding
// (bottom-first, so the last is the top of the pile). Capacity and ordering
// rules can join it later without touching the view.
type pile = {stacking: stacking, cards: array<card>}

type t = {
  id: string, // stable scene id (also the picker / localStorage key)
  name: string, // human label shown in the scene picker
  piles: array<pile>,
  free: bool,
  loose: array<card>,
  caption: option<string>, // prose shown beneath the board; `None` for none
}

// The card-stacking demo, now as data: two empty piles (one squared, one
// fanned), free drops allowed, opening with three loose cards.
let stacking = {
  id: "stacking",
  name: "Stacking",
  piles: [{stacking: Squared, cards: []}, {stacking: Fanned, cards: []}],
  free: true,
  loose: [{suit: Spades, rank: Ace}, {suit: Hearts, rank: King}, {suit: Diamonds, rank: Seven}],
  caption: Some("Drag the cards onto a slot to pile them up, or drop them loose on the table."),
}

// A second game with different rules, proving the view interprets the model
// rather than baking in the demo: four fanned piles, drops confined to the piles
// (`free: false`, #63), opening with a couple of cards already dealt into each
// pile and nothing loose on the table.
let fourFans = {
  id: "four-fans",
  name: "Four Fans",
  piles: [
    {stacking: Fanned, cards: [{suit: Clubs, rank: Two}, {suit: Diamonds, rank: Five}]},
    {stacking: Fanned, cards: [{suit: Hearts, rank: Nine}, {suit: Spades, rank: Jack}]},
    {stacking: Fanned, cards: [{suit: Clubs, rank: Queen}, {suit: Hearts, rank: Three}]},
    {stacking: Fanned, cards: [{suit: Spades, rank: Seven}, {suit: Diamonds, rank: Ten}]},
  ],
  free: false,
  loose: [],
  caption: Some("Drag the cards between the slots — they can only rest in a pile."),
}

// Every supported game, in picker order.
let all = [stacking, fourFans]
