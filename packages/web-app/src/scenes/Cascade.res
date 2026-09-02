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
// `cardWidth` it multiplies by when it draws). Metres are the same bargain in the other
// direction: a card-width *is* a length (`toMetric`), so a person can read the gravity
// as m/s² — but the conversion sits at the edge a person meets, never in `step`.
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

// --- Card-widths as a length --------------------------------------------------

// A card-width is 2.5 inches of real card (`CardArt.widthMetres`), which is what lets a
// gravity in card-widths per second squared be read as one in m/s² — and *only* read as
// one. The simulation stays in card-widths, because that is what makes it the same
// motion at a 40px card and a 140px one; metres are how a person judges the number, so
// the conversion belongs at the edge where a person meets it, next to `snapToDevice`
// rather than inside `step`.
//
// Worth knowing before reaching for the slider: at the default gravity a card falls at
// about four tenths of a g. Earth is `fromMetric(9.81)`, a shade over 154 card-widths
// per second squared.
let metresPerCardWidth = CardArt.widthMetres

// Card-widths to metres, and back. Every quantity here is a length or a length per
// second, so one pair covers speeds and accelerations alike.
let toMetric = value => value *. metresPerCardWidth
let fromMetric = value => value /. metresPerCardWidth

// Earth's, for a scene that wants to say how far from it a setting is.
let earthGravity = 9.80665

// One card in flight: where it is, how fast, in card-widths — and how well it bounces,
// which is the card's own rather than the run's. Drawn once at launch and carried, so a
// card keeps the character it left with instead of picking a new one off every floor.
type flyer = {card: Deck.card, x: float, y: float, vx: float, vy: float, bounciness: float}

// The arena, in card-widths, and the seats cards launch from — top-left corners, taken
// in turn. Seats are the stage's rather than a knob because the integration's are the
// board's foundations, which are wherever the board put them. Taking them in turn is
// what makes a seat a foundation: `foundationOrder` deals in the same round-robin, so
// with four of each every card leaves from the pile it sat on.
type stage = {width: float, height: float, seats: array<(float, float)>}

// The feel, all of it. On screen in the scene rather than in here, because whether a
// cascade looks right is not a question source can answer (see CascadeScene).
// **Anything a card can differ in is a value and a ± around it**, drawn once, when the
// card launches. Not a low and a high: a pair of ends is two numbers to drag to move one
// thing, and which of them is "the speed" has no answer. A centre and a spread has both
// — the centre is the cascade's character and the spread is how much the deck varies
// from it, and either can be moved without touching the other. A spread of 0 is 52
// identical cards, which is the setting that shows what the spread was doing.
type knobs = {
  gravity: float, // card-widths / s²
  // The fraction of falling speed a bounce keeps. Physics calls this the coefficient of
  // restitution; the plainer word is the one on the slider, and 0 to 1 means the same
  // thing either way — 0 lands dead, 1 would bounce back to where it fell from.
  bounciness: float,
  bouncinessVariance: float,
  speed: float, // horizontal launch speed, card-widths / s
  speedVariance: float,
  launchMs: float, // between one card leaving and the next
}

// Tuned by dragging the sliders in `CascadeScene` until it looked right, which is what
// that scene is for. On a desktop stage a card falls its height in about four tenths of
// a second, takes two to cross, and bounces half a dozen times on the way — a card at a
// time, three quarters of a second apart, so the deck is most of a minute.
//
// **Written in the unit the sliders read them in**, so the scene opens on the numbers
// that were chosen rather than on whatever they come to in card-widths. What they come
// to is four tenths of a g and a gentle toss: this is slow motion, and saying so in
// metres is the point of saying it in metres at all.
let defaults = {
  gravity: fromMetric(4.),
  bounciness: 0.8,
  bouncinessVariance: 0.15,
  speed: fromMetric(0.4),
  speedVariance: fromMetric(0.1),
  launchMs: 750.,
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

// How hard a card is aimed away from the nearer wall.
//
// Which way a card goes is a coin flip, and from a seat close to an edge half of them
// were leaving over that edge a card-width later — gone before they had crossed
// anything, which is a card of the deck spent on nothing. So the coin is weighted by
// how much room there is each way: the same two distances `hasLeft` retires a card at,
// read forwards instead of backwards.
//
//   p(right) = 0.5 + inwardBias × (roomRight / (roomLeft + roomRight) − 0.5)
//
// At 0 the coin is fair and this changes nothing; at 1 — here — the chance is exactly
// the share of the room, so the leftmost of four seats sends about one card in five
// over the near wall instead of one in two, and a seat with equal room either way stays
// a fair coin however hard the thumb presses. Above 1 it leans harder than the room
// warrants, which is what the clamp in `rightwardChance` is for.
//
// Deliberately a constant rather than a slider: a card that ducks out early is worth
// seeing *sometimes* — it is where the cascade looks least mechanical — and this is the
// setting where it happens without being half of what you watch.
let inwardBias = 1.

// The chance a card launched from `seatX` is thrown to the right. See `inwardBias`; the
// clamp is what keeps a bias over 1, or a seat already off the edge, from asking for a
// chance outside [0, 1].
let rightwardChance = (~seatX, ~stage: stage) => {
  let roomLeft = Math.max(seatX +. 1., 0.)
  let roomRight = Math.max(stage.width -. seatX, 0.)
  let room = roomLeft +. roomRight
  let share = room > 0. ? roomRight /. room : 0.5
  Math.min(Math.max(0.5 +. inwardBias *. (share -. 0.5), 0.), 1.)
}

// A value scattered around its centre: `value ± variance`, uniform, one draw. Held
// inside `[low, high]` so a spread wider than the value has somewhere to land — a
// negative speed would be a direction (which is `rightwardChance`'s business, not the
// spread's), and a bounciness over 1 is a card that gains energy off the floor and never
// comes down.
let scatter = (~value, ~variance, ~low, ~high, unit) =>
  Math.min(Math.max(value +. (unit *. 2. -. 1.) *. variance, low), high)

// The next card off the pile, given the seat it launches from and three draws: how fast
// it goes sideways, which way, and how well it bounces. Nothing is thrown upwards — a
// card leaves its seat at rest vertically, so every card traces the same parabola family
// and the picture reads as one cascade rather than as 52 unrelated throws.
let spawn = (rng, ~knobs, ~stage, ~card, ~seat) => {
  let (rng, speedDraw) = draw(rng)
  let (rng, sideDraw) = draw(rng)
  let (rng, bounceDraw) = draw(rng)
  let (seatX, seatY) = seat
  let speed = scatter(
    ~value=knobs.speed,
    ~variance=knobs.speedVariance,
    ~low=0.,
    ~high=Float.Constants.positiveInfinity,
    speedDraw,
  )
  let bounciness = scatter(
    ~value=knobs.bounciness,
    ~variance=knobs.bouncinessVariance,
    ~low=0.,
    ~high=1.,
    bounceDraw,
  )
  let rightward = sideDraw < rightwardChance(~seatX, ~stage)
  (rng, {card, x: seatX, y: seatY, vx: rightward ? speed : -.speed, vy: 0., bounciness})
}

// One card, one step. Gravity into the velocity, velocity into the position, and the
// floor caught on the way past — off the card's own bounciness, not the run's, which is
// what makes a spread something you can see rather than an average you can't.
let advance = (flyer, ~knobs, ~stage, ~dt) => {
  let vy = flyer.vy +. knobs.gravity *. dt
  let y = flyer.y +. vy *. dt
  let x = flyer.x +. flyer.vx *. dt
  let floor = floorOf(stage)
  if y >= floor && vy > 0. {
    {...flyer, x, y: floor, vy: -.vy *. flyer.bounciness}
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
    let (next, flyer) = spawn(rng.contents, ~knobs, ~stage, ~card, ~seat)
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
// next bounce, and a bounce that depends on the display is a bug you cannot see.
let snapToDevice = (value, ~ratio) => ratio > 0. ? Math.round(value *. ratio) /. ratio : value
