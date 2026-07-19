// Stackability rules: whether a candidate card may land on a pile, decided by a
// single *pure* predicate over card identities. This is Step 1 of the
// roadmap-to-M1 sketch (#75): the decision is a standalone function rather than
// logic inlined in the pointer/drop handler, even though the game state is still
// view-owned for now.
//
// Keeping it here — pure and free of any view or DOM concern — means the later
// M1 migration relocates it into a reducer (`Rules.canDrop`) instead of
// rewriting it, and it is unit-testable immediately (see `Core_test`). Each pile
// carries the `rule` it enforces (`Game.pile.rule`); the view's hover highlight
// and its drop-accept/reject decision call `accepts` with that rule, so the
// green "valid" outline and the accepted drop can never disagree.
//
// #76 generalises #75's single hard-coded rule into *data* — a `rule` per pile —
// so one board can carry piles that stack by different laws (a #75 alternating
// tableau and a same-suit foundation) with no rule-specific code path: both are
// values of the same `rule` type, weighed by the same `accepts`.

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

// --- Rule as data (#76) ------------------------------------------------------
// A pile's stacking law, described by three independent knobs so today's two
// ordered behaviours — #75's tableau and a foundation — and a future FreeCell
// cascade all fall out of one type rather than bespoke branches. The permissive
// free-arrangement mode is the one law that constrains nothing, so it's its own
// `Free`; every *ordered* pile is a parameterised `Ordered`.

// Which way an ordered pile climbs the Ace→King run, rank by rank.
type direction =
  | Up // ascends: each card one rank higher (foundations; #75's tableau)
  | Down // descends: each card one rank lower (a future FreeCell cascade)

// How an ordered pile constrains a newcomer's colour/suit against the card below.
type colorRule =
  | Any // colour is unconstrained
  | Alternating // opposite colour of the card below (#75's tableau)
  | SameSuit // same suit as the card below (a foundation, building up by suit)

// What may land on an *empty* pile — its opening move.
type emptyRule =
  | AnyCard // any card founds the pile (#75's tableau)
  | AceOnly // only an Ace opens the pile (a foundation builds up from the Ace)

// A pile's rule, as data. `Ordered` climbs (or descends) rank by rank under a
// colour and empty-pile constraint; `Free` accepts anything (the
// free-arrangement card-table demos, which don't order their piles).
type rule =
  | Ordered({direction: direction, color: colorRule, empty: emptyRule})
  | Free

// #75's tableau, now as data: climb Ace→King, each card the opposite colour of
// the one below, any card founding the empty pile.
let tableau = Ordered({direction: Up, color: Alternating, empty: AnyCard})

// A foundation: build up by suit from the Ace — same suit, one rank higher each
// time, and only an Ace may open the empty pile.
let foundation = Ordered({direction: Up, color: SameSuit, empty: AceOnly})

// A FreeCell cascade (M2): build *down* in alternating colour — a black Six
// lands on a red Seven — with any card founding an empty column. The mirror
// image of the ascending `tableau`, and the first (and only) user of the `Down`
// direction.
let cascade = Ordered({direction: Down, color: Alternating, empty: AnyCard})

// May `candidate` be stacked on a pile governed by `rule` whose current top card
// is `onto` (`None` for an empty pile)? The one predicate every pile is weighed
// by: an empty pile consults its `empty` rule, and a non-empty one must satisfy
// both the colour constraint and the one-rank step in the pile's direction.
let accepts = (rule: rule, candidate: card, onto: option<card>): bool =>
  switch rule {
  | Free => true
  | Ordered({direction, color: colorRule, empty}) =>
    switch onto {
    | None =>
      switch empty {
      | AnyCard => true
      | AceOnly => candidate.rank == Ace
      }
    | Some(top) =>
      let colorOk = switch colorRule {
      | Any => true
      | Alternating => color(candidate.suit) != color(top.suit)
      | SameSuit => candidate.suit == top.suit
      }
      let rankOk = switch direction {
      | Up => rankValue(candidate.rank) == rankValue(top.rank) + 1
      | Down => rankValue(candidate.rank) == rankValue(top.rank) - 1
      }
      colorOk && rankOk
    }
  }

// Do `cards` (bottom-first, as a pile holds them) form a legal run under `rule` —
// each card lawfully stacked on the one below it? This is the pairwise reading of
// `accepts` that the supermove (#123) lifts a span by: the maximal *tail* of a
// cascade that is a run is the most that may move at once. A run of zero or one
// card is trivially a run (nothing to disagree), and the bottom card founds the
// run so it's unconstrained here — `isRun` judges only the internal ordering, not
// where the run would land (that's `accepts` against the destination's top).
let isRun = (rule: rule, cards: array<card>): bool =>
  cards
  ->Array.mapWithIndex((card, i) =>
    switch cards->Array.get(i - 1) {
    | Some(below) => accepts(rule, card, Some(below))
    | None => true // the bottom card founds the run
    }
  )
  ->Array.every(x => x)

// Has a pile completed a full run? True when it holds all thirteen ranks
// Ace→King, i.e. thirteen cards ending on the King — the "done" moment a
// foundation builds toward (#76). This only *signals* a finished pile; full win
// detection across every foundation is later.
let isCompleteRun = (cards: array<card>): bool =>
  switch cards->Array.get(Array.length(cards) - 1) {
  | Some(top) => top.rank == King && Array.length(cards) == 13
  | None => false
  }
