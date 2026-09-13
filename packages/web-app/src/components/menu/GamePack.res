// The pack a board is played with, as a control wears it: "♠♥ ×2" — which suits are in
// play, and how many times each card is in the deck. What the Games list's Spiderette
// row shows on the segment that changes it (`MenuGameRow`).
//
// **Read off the deck, not tabulated beside the games.** It is the same half of
// `GameInfo`'s reasoning: a board that changes its pack says so here without an edit,
// and there is nothing to leave behind out of step.

// `copies` is `None` on a single pack, where "×1" is a number a reader has to discard —
// four suits with nothing after them is the standard deck, and says so shorter.
type t = {
  // The pips, in the deck's own order: "♠", "♠♥", "♠♥♦♣".
  suits: string,
  copies: option<string>,
  // The same fact in words, for the accessible name of a control wearing it — pips are
  // read out as anything from "black spade suit" to nothing at all.
  name: string,
}

let forDeck = (deck: Cards.deck): t => {
  let count = Array.length(deck.suits)
  {
    suits: deck.suits->Array.map(Deck.suitSymbol)->Array.join(""),
    copies: deck.copies > 1 ? Some("×" ++ Int.toString(deck.copies)) : None,
    name: Int.toString(count) ++ (count == 1 ? " suit" : " suits"),
  }
}
