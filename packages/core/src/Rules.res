// Stackability rules: whether a candidate card may land on a pile, decided by a
// single *pure* predicate over card identities — a standalone function rather
// than logic inlined in the pointer/drop handler, free of any view or DOM
// concern and unit-testable on its own (see `Core_test`).
//
// Each pile carries the `rule` it enforces (`Game.pile.rule`); the view's hover
// highlight and its drop-accept/reject decision call `accepts` with that rule,
// so the green "valid" outline and the accepted drop can never disagree.
//
// A rule is *data* — one per pile — so a board can carry piles that stack by
// different laws (an alternating-colour tableau and a same-suit foundation) with
// no rule-specific code path: both are values of the same `rule` type, weighed by
// the same `accepts`.
//
// A rule answers two questions, not one. `accepts` is what may *land*; `isRun` is
// what holds together and may be *lifted* as one. In FreeCell the two coincide, so
// they read as one law. In Spider they don't: any card one rank lower may land
// (`spiderCascade`), but only a same-suit run moves as a unit — which is why an
// `Ordered` rule carries a colour law for each.

open Card

// The two card colours. The alternating-colour rule cares only about this
// coarser distinction, not the suit itself — hearts and diamonds are red; spades
// and clubs black. (The presentation layer has its own `suitColor` for the ink;
// this is the model's notion, so the rule stays presentation-free.)
type color =
  | Red
  | Black

let color = suit =>
  switch suit {
  | Hearts | Diamonds => Red
  | Spades | Clubs => Black
  }

// A rank's position in the Ace→King run, so "ascends consecutively" is just a
// `+ 1` comparison. Ace is the low end (1), King the high end (13).
let rankValue = rank =>
  switch rank {
  | Ace => 1
  | Two => 2
  | Three => 3
  | Four => 4
  | Five => 5
  | Six => 6
  | Seven => 7
  | Eight => 8
  | Nine => 9
  | Ten => 10
  | Jack => 11
  | Queen => 12
  | King => 13
  }

// --- Rule as data ------------------------------------------------------
// A pile's stacking law, described by three independent knobs so today's two
// ordered behaviours — an alternating tableau and a foundation — and a future FreeCell
// cascade all fall out of one type rather than bespoke branches. The permissive
// free-arrangement mode is the one law that constrains nothing, so it's its own
// `Free`; every *ordered* pile is a parameterised `Ordered`.

// Which way an ordered pile climbs the Ace→King run, rank by rank.
type direction =
  | Up // ascends: each card one rank higher (a foundation)
  | Down // descends: each card one rank lower (a FreeCell cascade)

// How an ordered pile constrains a newcomer's colour/suit against the card below.
type colorRule =
  | Any // colour is unconstrained
  | Alternating // opposite colour of the card below (a FreeCell cascade)
  | SameSuit // same suit as the card below (a foundation, building up by suit)

// What may land on an *empty* pile — its opening move.
type emptyRule =
  | AnyCard // any card founds the pile (a FreeCell cascade)
  | AceOnly // only an Ace opens the pile (a foundation builds up from the Ace)

// A pile's rule, as data. `Ordered` climbs (or descends) rank by rank under a
// colour and empty-pile constraint, with `run` the colour law that holds a lifted
// run together (`isRun`) — `color` is what a newcomer must be against the card
// below, `run` what each card of a span must be against the one under it. `Free`
// accepts anything (a free cell, which takes any single card). `Sealed` accepts
// nothing and lets nothing be lifted: a pile only the game itself fills, by
// collecting a completed run (`Reducer.autoCollect`), and never the hand.
type rule =
  | Ordered({direction: direction, color: colorRule, run: colorRule, empty: emptyRule})
  | Free
  | Sealed

// A foundation: build up by suit from the Ace — same suit, one rank higher each
// time, and only an Ace may open the empty pile.
let foundation = Ordered({direction: Up, color: SameSuit, run: SameSuit, empty: AceOnly})

// A FreeCell cascade: build *down* in alternating colour — a black Six
// lands on a red Seven — with any card founding an empty column. The mirror
// image of the ascending `foundation`, and a run is read by the same law it lands by.
let cascade = Ordered({direction: Down, color: Alternating, run: Alternating, empty: AnyCard})

// A Spider cascade (Spider, Simple Simon): build down *regardless of suit* — any
// Six lands on any Seven — with any card founding an empty column, but a run is
// only a run while it stays in **one suit**. So a ♥7 landing on a ♠8 is a lawful
// drop that heads no run: the ♠8 and the ♥7 never move together again until one of
// them leaves.
let spiderCascade = Ordered({direction: Down, color: Any, run: SameSuit, empty: AnyCard})

// The two halves of "lawfully on top of": the colour law, and the one-rank step in
// the pile's direction. Split out because `accepts` and `isRun` apply them under
// *different* colour laws — the same step, a different `colorRule`.
let colorOk = (colorRule: colorRule, upper: card, lower: card): bool =>
  switch colorRule {
  | Any => true
  | Alternating => color(upper.suit) != color(lower.suit)
  | SameSuit => upper.suit == lower.suit
  }

let stepOk = (direction: direction, upper: card, lower: card): bool =>
  switch direction {
  | Up => rankValue(upper.rank) == rankValue(lower.rank) + 1
  | Down => rankValue(upper.rank) == rankValue(lower.rank) - 1
  }

// May `candidate` be stacked on a pile governed by `rule` whose current top card
// is `onto` (`None` for an empty pile)? The one predicate every pile is weighed
// by: an empty pile consults its `empty` rule, and a non-empty one must satisfy
// both the colour constraint and the one-rank step in the pile's direction.
let accepts = (rule: rule, candidate: card, onto: option<card>): bool =>
  switch rule {
  | Free => true
  | Sealed => false
  | Ordered({direction, color: colorRule, empty}) =>
    switch onto {
    | None =>
      switch empty {
      | AnyCard => true
      | AceOnly => candidate.rank == Ace
      }
    | Some(top) => colorOk(colorRule, candidate, top) && stepOk(direction, candidate, top)
    }
  }

// Do `cards` (bottom-first, as a pile holds them) form a legal run under `rule` —
// each card lawfully on the one below it, under the rule's `run` colour law and its
// step? This is what a hand lifts a span by: the maximal *tail* of a cascade that
// is a run is the most that may move at once. A run of zero or one card is
// trivially a run (nothing to disagree), and the bottom card founds the run so it's
// unconstrained here — `isRun` judges only the internal ordering, not where the run
// would land (that's `accepts` against the destination's top). Nothing on a `Sealed`
// pile is a run, not even its top card alone: nothing there is the hand's to lift.
let isRun = (rule: rule, cards: array<card>): bool =>
  switch rule {
  | Free => true
  | Sealed => false
  | Ordered({direction, run}) =>
    cards
    ->Array.mapWithIndex((card, i) =>
      switch cards->Array.get(i - 1) {
      | Some(below) => colorOk(run, card, below) && stepOk(direction, card, below)
      | None => true // the bottom card founds the run
      }
    )
    ->Array.every(x => x)
  }

// Has a pile completed a full run? True when it holds *every rank of `deck`* in one
// suit, consecutively, reaching the deck's highest — the "done" moment a foundation
// builds toward. Either way up: a FreeCell foundation ends Ace-to-King, a Spider
// foundation holds the King-to-Ace run lifted off a cascade, and both are the one
// complete run of a suit. This only *signals* a finished pile; win detection across
// every foundation is `GameState.hasWon`.
//
// The deck is a parameter rather than the ambient pack: `top.rank == King &&
// Array.length(cards) == 13` would hard-code the 52-card deck into what "complete"
// means. For `Cards.standard` the two say exactly the same thing — thirteen ranks, King
// highest — so the difference shows only on a shorter deck, which is where it matters.
//
// "Highest" is by `rankValue`, not by position in `deck.ranks`, so a deck listing
// its ranks out of order still answers the same.
let isCompleteRun = (~deck: Cards.deck, cards: array<card>): bool => {
  let highest = deck.ranks->Array.reduce(0, (best, rank) => Math.Int.max(best, rankValue(rank)))
  let consecutive = (direction: direction) =>
    cards->Array.everyWithIndex((card, i) =>
      switch cards->Array.get(i - 1) {
      | Some(below) => stepOk(direction, card, below)
      | None => true
      }
    )
  switch cards->Array.get(0) {
  | None => false // an empty pile is never complete — not even for an empty deck
  | Some(bottom) =>
    Array.length(cards) == Array.length(deck.ranks) &&
    cards->Array.every(c => c.suit == bottom.suit) &&
    (consecutive(Up) || consecutive(Down)) &&
    cards->Array.some(c => rankValue(c.rank) == highest)
  }
}
