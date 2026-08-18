// The **name each slot on the board answers to** — `T3`, `C1`, `F4` — and the
// translation between those names and the pile indices the reducer moves cards
// between.
//
// It exists because two callers have to agree on it. `Render` prints the name as a
// heading above the column, and `Command` reads one back when a move names its
// destination that way (`move 2H T3`). A label the board prints but the parser won't
// take — or the reverse — is worse than no label at all, so both go through here.
//
// The scheme is a role letter and a 1-based ordinal *within that role*:
//
//   T1…T8   the tableau columns (this model's `Cascade` piles)
//   C1…C4   the free cells
//   F1…F4   the foundations
//
// Letter first, deliberately. A card is named rank-then-suit (`3C` is the Three of
// Clubs — see `CardText`), so a digit-first `3C` would be two different things in the
// one place both can appear: a move's destination. `C3` can only ever be the cell.
//
// The ordinal counts within the role rather than across the board, so it names what a
// player sees ("the third column") rather than the absolute pile index the model uses
// — on a FreeCell board `T1` is pile 8. The indices are still what `move <card> <n>`
// takes and what the reducer speaks; this is a second, kinder way to say one.

// The letter that stands for each role. `T` for the tableau columns rather than `C`
// for cascade, because `C` is the free cells' and a player calls that row the tableau.
let letter = (role: Game.role): string =>
  switch role {
  | Game.Cascade => "T"
  | Game.FreeCell => "C"
  | Game.Foundation => "F"
  }

// The role a letter stands for, case-insensitively — the inverse of `letter`.
let roleFor = (s: string): option<Game.role> =>
  switch s->String.toUpperCase {
  | "T" => Some(Game.Cascade)
  | "C" => Some(Game.FreeCell)
  | "F" => Some(Game.Foundation)
  | _ => None
  }

// What to call a role in prose, singular — for the refusals below ("this board has no
// free cells"), so a message names the thing a player sees rather than the variant.
let roleName = (role: Game.role): string =>
  switch role {
  | Game.Cascade => "tableau column"
  | Game.FreeCell => "free cell"
  | Game.Foundation => "foundation"
  }

let roleNamePlural = (role: Game.role): string =>
  switch role {
  | Game.Cascade => "tableau columns"
  | Game.FreeCell => "free cells"
  | Game.Foundation => "foundations"
  }

// A label from its parts: `T` + `3`.
let format = (~role: Game.role, ~ordinal: int): string => letter(role) ++ Int.toString(ordinal)

// How many slots of a role a board has — what an out-of-range ordinal is measured
// against, and what tells a game that has none of a role from one that has a few.
let count = (~game: Game.t, role: Game.role): int => Array.length(Game.pileIndices(game, role))

// The pile index a (role, ordinal) names on this board, or `None` when the board has
// no such slot. Ordinals are 1-based, so `T1` is the first cascade.
let indexOf = (~game: Game.t, ~role: Game.role, ~ordinal: int): option<int> =>
  Game.pileIndices(game, role)->Array.get(ordinal - 1)

// The label for a pile index on this board — its role's letter and its position within
// that role — or `None` when the index isn't a pile of this board.
let labelAt = (~game: Game.t, i: int): option<string> =>
  switch game.piles->Array.get(i) {
  | None => None
  | Some(pile) =>
    switch Game.pileIndices(game, pile.role)->Array.findIndex(j => j == i) {
    | -1 => None
    | at => Some(format(~role=pile.role, ~ordinal=at + 1))
    }
  }

// Read a label back: a role letter followed by an all-digit, 1-based ordinal.
// Case-insensitive, like the card identities beside it. The digits are checked
// character by character rather than left to `Int.fromString`, which would read
// `T3x` as the third column and quietly move a card somewhere nobody asked for.
let parse = (token: string): option<(Game.role, int)> => {
  let s = token->String.trim
  if String.length(s) < 2 {
    None
  } else {
    let digits = s->String.sliceToEnd(~start=1)
    let allDigits = digits->String.split("")->Array.every(c => c >= "0" && c <= "9")
    switch (roleFor(s->String.slice(~start=0, ~end=1)), allDigits ? Int.fromString(digits) : None) {
    | (Some(role), Some(ordinal)) if ordinal >= 1 => Some((role, ordinal))
    | _ => None
    }
  }
}

// Every label a board offers, in board order — what a refusal lists so the reader can
// see what *would* have worked.
let labels = (~game: Game.t): array<string> =>
  game.piles->Array.mapWithIndex((_, i) => labelAt(~game, i))->Array.filterMap(l => l)
