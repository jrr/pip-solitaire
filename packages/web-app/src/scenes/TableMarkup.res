// The table's markup, as vnodes: the elements `TableScene.css` styles. Two things
// render a board — the live table (`TableScene`), which creates each node once and then
// moves it, and the still of the opening board on a game's info screen
// (`BoardPreview`), which renders the whole tree at once — and both build it from here,
// so a class name the stylesheet answers to is written in one place and the two trees
// can't drift apart under the same rules.
//
// Nothing here is *positioned*. A row spreads its zones, a `rest` box sits where a
// squared card rests, and where a fanned card steps to is the caller's: the table writes
// `left`/`top` on the playfield, the still a margin on the rest box. What varies with
// state — the down class, the tilt property — is taken as arguments, so the still can
// state it up front where the table sets it on the node later (`setFaceDown`,
// `applyTilt`).

// The sheet these names answer to. `TableScene` imports it too; this import is what
// keeps the markup styled where it is rendered without the table — the info screen.
%%raw(`import "./TableScene.css"`)

// The role-grouped rows of zones, and one row of them.
let rows = (~style=?, ~ariaHidden=?, children: Html.vnode) =>
  <div className="drop-rows" style=?{style} ariaHidden=?{ariaHidden}> {children} </div>

let row = (children: Html.vnode) => <div className="drop-row"> {children} </div>

// One pile's zone: the hit-test box on the table, and the box its cards sit in on
// the still. `style` is the grown height of a fanned zone, when the caller knows it.
let zone = (~style=?, children: Html.vnode) =>
  <div className="drop-zone" style=?{style}> {children} </div>

// The modifier the empty-pile indicator wears for its pile's role. The three
// roles accept quite different things — a foundation only ever opens with an Ace, a
// free cell takes any one card, a tableau column takes a card or a run — and one
// dashed rectangle for all three leaves a player unable to tell where the cells end
// and the foundations begin. That boundary isn't learnable by position either: it
// moves with the game (`freecell` is 4 cells + 4 foundations, `mini` 2 + 4, `micro`
// 2 + 2), which is why the cue has to be intrinsic to the slot rather than a gap in
// the row.
//
// Only the *paint* varies. The footprint stays identical across the three — the slot
// traces the card exactly, and browser-tests/geometry.spec.mjs pins that on whichever
// slot comes first (a free cell) — so a role may change colour, fill and contents,
// but never its size or corner radius.
let slotRoleClass = (role: Game.role) =>
  switch role {
  | Game.FreeCell => "drop-zone__slot--cell"
  | Game.Foundation => "drop-zone__slot--foundation"
  | Game.Cascade => "drop-zone__slot--tableau"
  | Game.Stock => "drop-zone__slot--stock"
  }

// The static empty-pile indicator: a card-sized box on the resting place
// (`drop-zone__rest`), painted for its role. A resting card covers it pixel for pixel,
// so the cue shows only on an empty pile.
let slot = (role: Game.role) =>
  <div className={"drop-zone__slot drop-zone__rest " ++ slotRoleClass(role)} />

// A card-sized box centred where a squared card rests, with nothing painted on it: the
// still puts each card in one, stepped down the fan by a margin.
let rest = (~style=?, children: Html.vnode) =>
  <div className="drop-zone__rest" style=?{style}> {children} </div>

// One card: the face, and behind it the back the stylesheet shows while the wrapper
// carries the down class. The back is a plain element rather than a second piece of
// card art: it carries no identity, and one per card is cheap where another SVG isn't.
let card = (~down=false, ~tilt: option<float>=?, data: Deck.card) =>
  <div
    className={down ? "stacking-card stacking-card--down" : "stacking-card"}
    style=?{tilt->Option.map(degrees => `--card-rot: ${Float.toString(degrees)}deg`)}
  >
    {CardArt.svg(data)}
    <div className="card-back" ariaHidden="true" />
  </div>
