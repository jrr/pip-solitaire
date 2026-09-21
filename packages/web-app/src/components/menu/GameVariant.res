// What the Games list's variant segment shows for one board of a family, and how it is
// spoken. Two shapes, because the families are told apart two different ways
// (`Game.mark`): the Spiderettes by the deck itself, the FreeCells by a word.
//
// **The pack is read off the deck, not tabulated beside the games.** It is the same half
// of `GameInfo`'s reasoning: a board that changes its pack says so here without an edit,
// and there is nothing left behind to go out of step. A word has nothing to read it off
// — that is exactly what makes it a word — so it comes from the family.

type mark =
  // The suits in play: "♠♥". How many times over the deck holds each of them is not
  // drawn — a pack is told from its siblings by its suits alone, and "×2" beside them is
  // arithmetic a reader has to do to learn nothing. The count is still said in `name`,
  // which is where a number belongs.
  | Pips(string)
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
    mark: Pips(deck.suits->Array.map(Deck.suitSymbol)->Array.join("")),
    name: Int.toString(count) ++ (count == 1 ? " suit" : " suits"),
    noun: "pack",
  }
}

let forVariant = (variant: Game.variant): t =>
  switch variant.mark {
  | Game.Pack => pips(variant.game.deck)
  | Game.Size(word) => {mark: Word(word), name: word, noun: "size"}
  }

// The word for what a *family* varies in, asked of the family rather than of one of its
// boards: a family is one kind of variant throughout — the Spiderettes are packs and the
// FreeCells sizes — so any of its variants answers for all of them, and the one that
// always exists is the default. It is what names the info screen's picker for a screen
// reader, which has a family in hand and no one board it is about.
let nounFor = (family: Game.family): string => forVariant(family.default).noun
