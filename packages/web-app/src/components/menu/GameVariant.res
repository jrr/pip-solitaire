// What the Games list's variant segment shows for one board of a family, and how it is
// spoken. Two shapes, because the families are told apart two different ways
// (`Game.mark`): the Spiderettes by the deck itself, the FreeCells by a word.
//
// **The pack is read off the deck, not tabulated beside the games.** It is the same half
// of `GameInfo`'s reasoning: a board that changes its pack says so here without an edit,
// and there is nothing left behind to go out of step. A word has nothing to read it off
// — that is exactly what makes it a word — so it comes from the family.

type mark =
  // The suits in play and how many times each card is in the deck: "♠♥" and "×2". Two
  // pieces because the stylesheet sets them differently, the pips being the content and
  // the multiplier only a qualifier on it. `copies` is `None` on a single pack, where
  // "×1" is a number a reader has to discard — four suits with nothing after them is the
  // standard deck, and says so shorter.
  | Pips({suits: string, copies: option<string>})
  | Word(string)

type t = {
  mark: mark,
  // The same fact in words, for the accessible name of the control wearing it — pips are
  // read out as anything from "black spade suit" to nothing at all.
  name: string,
  // …and the word for what this family varies in, so that control can say what it is
  // about: "Spiderette pack: 2 suits", "FreeCell size: Mini".
  noun: string,
}

let pips = (deck: Cards.deck): t => {
  let count = Array.length(deck.suits)
  {
    mark: Pips({
      suits: deck.suits->Array.map(Deck.suitSymbol)->Array.join(""),
      copies: deck.copies > 1 ? Some("×" ++ Int.toString(deck.copies)) : None,
    }),
    name: Int.toString(count) ++ (count == 1 ? " suit" : " suits"),
    noun: "pack",
  }
}

let forVariant = (variant: Game.variant): t =>
  switch variant.mark {
  | Game.Pack => pips(variant.game.deck)
  | Game.Size(word) => {mark: Word(word), name: word, noun: "size"}
  }
