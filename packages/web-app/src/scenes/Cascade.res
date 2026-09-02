// The victory cascade's motion: 52 cards launched one at a time, falling, bouncing
// off the floor with less energy each time, and leaving the stage at one side or the
// other. No canvas, no DOM, no clock — a run is a value, and `step` is the only thing
// that moves it — which is what lets `Cascade_test` check the physics without a
// browser, the same bargain `TableLayout` makes for the board's geometry.
//
// **Everything here is in card-widths and seconds.** A card is 1 wide and
// `cardHeight` tall, the stage is however many cards across it happens to be, and a
// speed is card-widths per second. Pixels never enter: they are the one unit that
// changes meaning between a 40px card on a phone and a 140px one on a desktop, and a
// gravity in pixels/s² makes the small board's cascade a slow drift and the large
// board's a plummet. `CascadePlayer` converts once, at the edge (`arenaOf`, and the
// `cardWidth` it multiplies by when it draws).
//
// **The integration is `v += g·dt; p += v·dt`, and `dt` is clamped here** rather than
// left to the caller. A frame's `dt` is whatever the display and the browser felt like
// giving: 8ms at 120Hz, 16 at 60, and *seconds* when a tab comes back from the
// background. Unclamped, that last one moves a card the length of the stage in a single
// step, straight through the floor. Clamped, a returning tab resumes where it left off
// — the run loses time, which is the right thing to lose.
//
// **Where the card lands on the floor is `Math.max`'d, not integrated.** A bounce sets
// the position to the floor rather than reflecting the overshoot, so no step size can
// tunnel a card through it, however fast the card is falling.
//
// Randomness is `Cards.xorshift`, threaded through the run as `rng`: a seed replays a
// cascade exactly, and `Math.random` stays banned. The launch *order* is the caller's
// (`~cards`), because the integration will hand over the cards the board's foundations
// give up, in the order they give them up — and with nothing handed over, the default is
// that same order played off a won game (`foundationOrder`).

// A card's height, in card-widths — the only proportion this module needs, and
// `CardArt` is where the app keeps it.
let cardHeight = CardArt.aspect

// One card in flight: where it is, and how fast, in card-widths.
type flyer = {card: Deck.card, x: float, y: float, vx: float, vy: float}

// The arena, in card-widths, and the seats cards launch from — top-left corners, taken
// in turn. Seats are the stage's rather than a knob because the integration's are the
// board's foundations, which are wherever the board put them. Taking them in turn is
// what makes a seat a foundation: `foundationOrder` deals in the same round-robin, so
// with four of each every card leaves from the pile it sat on.
type stage = {width: float, height: float, seats: array<(float, float)>}

// The feel, all of it. On screen in the scene rather than in here, because whether a
// cascade looks right is not a question source can answer (see CascadeScene).
type knobs = {
  gravity: float, // card-widths / s²
  restitution: float, // the fraction of falling speed a bounce keeps
  minSpeed: float, // horizontal launch speed, card-widths / s
  maxSpeed: float,
  launchMs: float, // between one card leaving and the next
}

// A starting point to tune away from: a card falls the height of a stage in about
// half a second, crosses it in two or three, and bounces four or five times on the way.
let defaults = {
  gravity: 26.,
  restitution: 0.62,
  minSpeed: 3.,
  maxSpeed: 7.,
  launchMs: 200.,
}

// A run in progress. `cards` is the launch order and never changes; `launched` is how
// far into it we are, so nothing is copied to consume it.
type t = {
  rng: int,
  cards: array<Deck.card>,
  launched: int,
  flying: array<flyer>,
  sinceLaunch: float, // seconds since the last card went
  retired: int,
}

// The longest step the physics will take, whatever it is handed. 50ms is three frames
// at 60Hz: long enough that an ordinary stutter passes through unaltered, short enough
// that a card moves a fraction of its own width in one.
let maxStep = 0.05

// One draw from the PRNG: the next state, and a float in [0, 1). The sign bit is masked
// off rather than folded in, so the draw is non-negative without a branch — the same
// move `Cards.shuffle` makes for the same reason.
let draw = (state: int) => {
  let next = Cards.xorshift(state)
  (next, Int.toFloat(next->Int.bitwiseAnd(0x7fffffff)) /. 2147483648.)
}

// --- What a won game leaves on the table --------------------------------------

// Which suit ended up on which foundation. That is the one thing a finished game
// varies — the piles themselves are always the same thirteen cards — so it is the one
// thing the seed picks here. A one-rank deck shuffled is exactly a permutation of the
// four suits, so `Cards.shuffle` does the drawing rather than a second Fisher–Yates.
let foundationSuits = (~seed) =>
  Cards.shuffle(~deck={suits: Cards.suits, ranks: [Deck.Ace]}, ~seed)->Array.map(card => card.suit)

// The deck in the order a won game gives it up: four complete foundations, each an A→K
// run with the King on top, taken from the top one pile at a time. So the cards come off
// by descending rank, four suits to a round, and the aces go last.
//
// The round-robin is the *same* round-robin `step` seats a card by, which is what keeps
// a suit falling from its own foundation the whole way down rather than wandering across
// the four seats.
let foundationOrder = (~seed): array<Deck.card> => {
  let suits = foundationSuits(~seed)
  Cards.ranks
  ->Array.toReversed
  ->Array.flatMap(rank => suits->Array.map((suit): Deck.card => {suit, rank}))
}

let make = (~seed: int, ~cards: option<array<Deck.card>>=?) => {
  rng: Cards.seedState(seed),
  cards: cards->Option.getOr(foundationOrder(~seed)),
  launched: 0,
  flying: [],
  // The first card goes on the first step (see `step`), so this starts at rest.
  sinceLaunch: 0.,
  retired: 0,
}

// Where the floor is, in card-widths: the card's *top* when it is resting on the
// bottom of the stage. Never above the ceiling, so a stage shorter than a card still
// has a floor a card can be put on rather than one it bounces below.
let floorOf = (stage: stage) => Math.max(stage.height -. cardHeight, 0.)

// The next card off the pile, given the seat it launches from and two draws: how fast
// it goes sideways, and which way. Speed is the only thing randomized — a card leaves
// its seat at rest vertically, so every card traces the same parabola family and the
// picture reads as one cascade rather than as 52 unrelated throws.
let spawn = (rng, ~knobs, ~card, ~seat) => {
  let (rng, speedDraw) = draw(rng)
  let (rng, sideDraw) = draw(rng)
  let (seatX, seatY) = seat
  let speed = knobs.minSpeed +. speedDraw *. Math.max(knobs.maxSpeed -. knobs.minSpeed, 0.)
  (rng, {card, x: seatX, y: seatY, vx: sideDraw < 0.5 ? -.speed : speed, vy: 0.})
}

// One card, one step. Gravity into the velocity, velocity into the position, and the
// floor caught on the way past.
let advance = (flyer, ~knobs, ~stage, ~dt) => {
  let vy = flyer.vy +. knobs.gravity *. dt
  let y = flyer.y +. vy *. dt
  let x = flyer.x +. flyer.vx *. dt
  let floor = floorOf(stage)
  if y >= floor && vy > 0. {
    {...flyer, x, y: floor, vy: -.vy *. knobs.restitution}
  } else {
    {...flyer, x, y, vy}
  }
}

// A card is done when it has left sideways — the whole card, so it doesn't blink out
// with an edge still showing. Nothing retires downwards: the floor is a floor.
let hasLeft = (flyer, ~stage: stage) => flyer.x +. 1. < 0. || flyer.x > stage.width

let isDone = run => run.launched == Array.length(run.cards) && Array.length(run.flying) == 0

// Advance the whole run by `dt` seconds (clamped, see `maxStep`): move what is in the
// air, drop what has left the stage, and launch whatever has come due.
let step = (run, ~knobs, ~stage, ~dt) => {
  let dt = Math.min(Math.max(dt, 0.), maxStep)
  // A zero interval would launch the deck in one step and, worse, spin the loop below
  // forever on a stage with cards left; a millisecond is as fast as the knob goes.
  let interval = Math.max(knobs.launchMs, 1.) /. 1000.

  let flying =
    run.flying
    ->Array.map(flyer => advance(flyer, ~knobs, ~stage, ~dt))
    ->Array.filter(flyer => !hasLeft(flyer, ~stage))
  let retired = run.retired + (Array.length(run.flying) - Array.length(flying))

  let rng = ref(run.rng)
  let launched = ref(run.launched)
  let sinceLaunch = ref(run.sinceLaunch +. dt)
  let seats = Array.length(stage.seats)
  let total = Array.length(run.cards)

  // The first card leaves the moment the run starts — waiting an interval for it reads
  // as the scene not having started. After that it is one card per interval, with the
  // remainder carried, so a launch rate faster than the frame rate still comes out right.
  while launched.contents < total && (launched.contents == 0 || sinceLaunch.contents >= interval) {
    let card = run.cards->Array.getUnsafe(launched.contents)
    let seat = seats == 0 ? (0., 0.) : stage.seats->Array.getUnsafe(mod(launched.contents, seats))
    let (next, flyer) = spawn(rng.contents, ~knobs, ~card, ~seat)
    rng := next
    flying->Array.push(flyer)
    launched := launched.contents + 1
    sinceLaunch := (launched.contents == 1 ? 0. : sinceLaunch.contents -. interval)
  }

  {
    rng: rng.contents,
    cards: run.cards,
    launched: launched.contents,
    flying,
    sinceLaunch: sinceLaunch.contents,
    retired,
  }
}

// --- The seam between card-widths and pixels ---------------------------------

// How high in the stage a card sits when it launches. Low enough to be clear of the
// top edge, high enough that the first fall is most of the stage.
let seatTop = 0.12

// Seats spread evenly across the top of the stage, `count` of them, each centred on its
// share of the width — the demo's stand-in for a row of foundations.
let spreadSeats = (~width, ~count) =>
  Array.fromInitializer(~length=count, index => (
    width *. Int.toFloat(index + 1) /. Int.toFloat(count + 1) -. 0.5,
    seatTop,
  ))

// A CSS-pixel box measured in card-widths. The one conversion in the whole model, and the
// reason nothing downstream of it has to know what a pixel is — separate from the stage
// it usually becomes, because a caller whose seats are its own (a board's foundations,
// rather than the spread below) still has to measure its arena by this and no other
// arithmetic.
let arenaOf = (~cssWidth, ~cssHeight, ~cardWidth) => {
  let scale = Math.max(cardWidth, 1.)
  (cssWidth /. scale, cssHeight /. scale)
}

// That box as a stage, with `count` seats spread across the top of it.
let stageOf = (~cssWidth, ~cssHeight, ~cardWidth, ~seats=4) => {
  let (width, height) = arenaOf(~cssWidth, ~cssHeight, ~cardWidth)
  {width, height, seats: spreadSeats(~width, ~count=seats)}
}

// Put a CSS-pixel coordinate on the *device*-pixel grid.
//
// Under the overlay's `ctx.scale(ratio, ratio)`, a whole CSS pixel is only a whole
// device pixel when the ratio is itself whole — and browser zoom reaches 1.5, 2.5, 3.75.
// Off the grid, every blit is resampled: the card comes out softer than the bitmap it
// was cut from, and because a resample acts about the centre it moves the card's two
// ends in opposite directions, which reads as the ends disagreeing rather than as blur.
//
// **Snap the drawing, never the simulation.** Quantising a position feeds back into the
// next bounce, and restitution that depends on the display is a bug you cannot see.
let snapToDevice = (value, ~ratio) => ratio > 0. ? Math.round(value *. ratio) /. ratio : value
