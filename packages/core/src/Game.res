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
//     Only `true` is supported for now (#62 doesn't ask for `false` yet), but
//     it's modelled so the rule lives with the game, not in the view.
//   - `loose` — the opening deal: specific cards resting free on the table.
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

// One drop zone. Today a pile is just its stacking behaviour; capacity and
// ordering rules can join it later without touching the view.
type pile = {stacking: stacking}

type t = {
  id: string, // stable scene id (also the picker / localStorage key)
  name: string, // human label shown in the scene picker
  piles: array<pile>,
  free: bool,
  loose: array<card>,
}

// The card-stacking demo, now as data: two piles (one squared, one fanned),
// free drops allowed, opening with three loose cards.
let stacking = {
  id: "stacking",
  name: "Stacking",
  piles: [{stacking: Squared}, {stacking: Fanned}],
  free: true,
  loose: [{suit: Spades, rank: Ace}, {suit: Hearts, rank: King}, {suit: Diamonds, rank: Seven}],
}

// A second game with different rules, proving the view interprets the model
// rather than baking in the demo: four fanned piles, free drops allowed, opening
// with a larger loose spread.
let fourFans = {
  id: "four-fans",
  name: "Four Fans",
  piles: [{stacking: Fanned}, {stacking: Fanned}, {stacking: Fanned}, {stacking: Fanned}],
  free: true,
  loose: [
    {suit: Clubs, rank: Two},
    {suit: Diamonds, rank: Five},
    {suit: Hearts, rank: Nine},
    {suit: Spades, rank: Jack},
    {suit: Clubs, rank: Queen},
  ],
}

// Every supported game, in picker order.
let all = [stacking, fourFans]
