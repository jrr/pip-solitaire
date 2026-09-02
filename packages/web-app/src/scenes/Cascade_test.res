// The cascade's motion, checked where it lives — in card-widths and seconds, with no
// canvas and no clock. What a browser is needed for (does a blit land on the device
// grid, does a seeded run redraw identically) is `browser-tests/cascade.spec.mjs`;
// everything below is arithmetic, and arithmetic is worth pinning here because the way
// this class of bug arrives is a cascade that still looks like a cascade.

open Vitest

// A stage with no floor and no sides worth reaching: the cases below that are about one
// card falling want gravity and nothing else.
let openStage: Cascade.stage = {width: 1000., height: 1000., seats: [(0., 0.)]}

// Straight down, at whatever gravity: a zero speed range takes the horizontal draw out
// of the picture without taking the PRNG out of it.
let dropping = {...Cascade.defaults, minSpeed: 0., maxSpeed: 0.}

let runFor = (~knobs, ~stage, ~seed=1, ~seconds, ~dt) => {
  let run = ref(Cascade.make(~seed, ~cards=Deck.allCards))
  let steps = Math.round(seconds /. dt)->Float.toInt
  for _ in 1 to steps {
    run := Cascade.step(run.contents, ~knobs, ~stage, ~dt)
  }
  run.contents
}

let first = (run: Cascade.t) => run.flying->Array.getUnsafe(0)

describe("the cascade's integration", () => {
  test("runs on the clock, not on frames — 120Hz doesn't fall twice as fast as 60Hz", () => {
    let at60 = runFor(~knobs=dropping, ~stage=openStage, ~seconds=1., ~dt=1. /. 60.)
    let at120 = runFor(~knobs=dropping, ~stage=openStage, ~seconds=1., ~dt=1. /. 120.)
    // A per-frame constant would put these a factor of two apart. What is left is
    // Euler's own step error, `g·T·dt/2` of extra fall — a tenth of a card-width
    // between these two rates, against the thirteen they both fall.
    expect(first(at60).y)->toBeCloseToWithin(first(at120).y, 0)
    expect(first(at120).y > 12.)->toBe(true)
  })

  test("clamps the step, so a tab coming back from the background can't teleport", () => {
    // Ten seconds of arrears in one call. Unclamped this lands the card 1300
    // card-widths down — through the floor of any stage, and off every one of the
    // bounces it should have taken on the way.
    let long = Cascade.step(
      Cascade.make(~seed=1, ~cards=Deck.allCards),
      ~knobs=dropping,
      ~stage=openStage,
      ~dt=10.,
    )
    let capped = Cascade.step(
      Cascade.make(~seed=1, ~cards=Deck.allCards),
      ~knobs=dropping,
      ~stage=openStage,
      ~dt=Cascade.maxStep,
    )
    expect(first(long).y)->toBe(first(capped).y)
  })

  test("catches the floor by position, so no step size can tunnel through it", () => {
    // A card moving faster than the stage is tall, in one step: the bounce is a
    // clamp, not a reflection of the overshoot, so where it ends up is the floor.
    let stage: Cascade.stage = {width: 20., height: 6., seats: [(5., 0.)]}
    let fast = {...dropping, gravity: 4000.}
    let run = runFor(~knobs=fast, ~stage, ~seconds=Cascade.maxStep, ~dt=Cascade.maxStep)
    expect(first(run).y <= Cascade.floorOf(stage))->toBe(true)
  })
})

describe("the bounce", () => {
  let stage: Cascade.stage = {width: 40., height: 8., seats: [(20., 0.)]}

  test("loses energy every time, so the apexes come down", () => {
    let dt = 1. /. 240.
    let run = ref(Cascade.make(~seed=1, ~cards=Deck.allCards))
    let apexes = []
    let rising = ref(false)
    for _ in 1 to 2000 {
      let before = first(run.contents)
      run := Cascade.step(run.contents, ~knobs=dropping, ~stage, ~dt)
      let after = first(run.contents)

      // The top of an arc: the card was going up and has started coming down.
      if rising.contents && after.vy >= 0. && before.vy < 0. {
        apexes->Array.push(after.y)
      }
      rising := after.vy < 0.
    }
    // Higher `y` is lower on the stage, so each apex sits further down than the last.
    // The first three, where the differences are card-widths: a card that has all but
    // stopped bouncing tops out a hair above the floor every time, and asserting on
    // *those* would be asserting on the last bits of a float.
    expect(Array.length(apexes) >= 3)->toBe(true)
    expect(apexes->Array.getUnsafe(0) < apexes->Array.getUnsafe(1))->toBe(true)
    expect(apexes->Array.getUnsafe(1) < apexes->Array.getUnsafe(2))->toBe(true)
  })

  test("keeps nothing at all at zero bounciness — the card just lands", () => {
    let dead = {...dropping, bounciness: 0.}
    let run = runFor(~knobs=dead, ~stage, ~seconds=3., ~dt=1. /. 120.)
    expect(first(run).y)->toBe(Cascade.floorOf(stage))
    // Through `Math.abs` because a bounce that keeps nothing negates a positive speed,
    // and the float that comes back is a signed zero.
    expect(Math.abs(first(run).vy))->toBe(0.)
  })

  test("puts the floor at the top of a stage too short to hold a card", () => {
    expect(Cascade.floorOf({width: 10., height: 1., seats: []}))->toBe(0.)
  })
})

describe("a seed", () => {
  let stage = Cascade.stageOf(~cssWidth=900., ~cssHeight=560., ~cardWidth=90.)
  let sample = seed =>
    runFor(~knobs=Cascade.defaults, ~stage, ~seed, ~seconds=2., ~dt=1. /. 120.).flying

  test("replays the cascade exactly", () => {
    expect(sample(7))->toEqual(sample(7))
  })

  test("and a different one doesn't", () => {
    expect(sample(7) == sample(8))->toBe(false)
  })
})

describe("card-widths as the unit", () => {
  test("a box is however many cards across it is, whatever a card costs in pixels", () => {
    let small = Cascade.stageOf(~cssWidth=800., ~cssHeight=600., ~cardWidth=40.)
    let large = Cascade.stageOf(~cssWidth=2800., ~cssHeight=2100., ~cardWidth=140.)
    expect(small)->toEqual(large)
    expect(small.width)->toBe(20.)
  })

  test("so the same board plays the same cascade at a 40px card and a 140px one", () => {
    // The claim the units exist for, and the one a gravity in pixels/s² breaks: the
    // *pictures* differ only in scale, because the physics can't tell the two apart.
    let at = cardWidth =>
      runFor(
        ~knobs=Cascade.defaults,
        ~stage=Cascade.stageOf(~cssWidth=20. *. cardWidth, ~cssHeight=15. *. cardWidth, ~cardWidth),
        ~seed=3,
        ~seconds=1.5,
        ~dt=1. /. 120.,
      ).flying
    expect(at(40.))->toEqual(at(140.))
  })
})

describe("the launch", () => {
  let stage = Cascade.stageOf(~cssWidth=900., ~cssHeight=560., ~cardWidth=90.)

  test("sends the first card immediately, then one per interval", () => {
    let run = runFor(
      ~knobs={...Cascade.defaults, launchMs: 200.},
      ~stage,
      ~seconds=1.1,
      ~dt=1. /. 120.,
    )
    // t=0, and then 0.2 through 1.0.
    expect(run.launched)->toBe(6)
  })

  test("stops when the deck does", () => {
    let three = Deck.allCards->Array.slice(~start=0, ~end=3)
    let run = ref(Cascade.make(~seed=1, ~cards=three))
    for _ in 1 to 600 {
      run := Cascade.step(run.contents, ~knobs=Cascade.defaults, ~stage, ~dt=1. /. 120.)
    }
    expect(run.contents.launched)->toBe(3)
  })

  test("spreads its seats across the top, so the deck doesn't pour from one place", () => {
    // Each seat centred on its share of the width — the demo's stand-in for a row of
    // foundations, and what the integration will replace with the real ones.
    expect(Cascade.spreadSeats(~width=20., ~count=4)->Array.map(((x, _)) => x))->toEqual([
      3.5,
      7.5,
      11.5,
      15.5,
    ])
    expect(Array.length(stage.seats))->toBe(4)
  })

  test("leaves its seat at rest, sideways, at a speed inside the range", () => {
    let (_, flyer) = Cascade.spawn(
      Cards.seedState(9),
      ~knobs=Cascade.defaults,
      ~stage,
      ~card={suit: Deck.Spades, rank: Deck.Ace},
      ~seat=(3.5, Cascade.seatTop),
    )
    expect(flyer.x)->toBe(3.5)
    expect(flyer.y)->toBe(Cascade.seatTop)
    // Nothing is thrown upwards: gravity is the whole of the vertical story, which is
    // what keeps 52 launches reading as one cascade.
    expect(flyer.vy)->toBe(0.)
    let speed = Math.abs(flyer.vx)
    expect(speed >= Cascade.defaults.minSpeed && speed <= Cascade.defaults.maxSpeed)->toBe(true)
  })
})

describe("which way a card is thrown", () => {
  // Eleven and a bit card-widths across, which is a desktop stage at a 90px card.
  let stage = Cascade.stageOf(~cssWidth=1056., ~cssHeight=560., ~cardWidth=90.)
  let seatX = index => stage.seats->Array.getUnsafe(index)->fst

  test("is an even coin from a seat with the same room either way", () => {
    // The middle of the stage, where there is nothing to prefer — and the two inner
    // seats of four, which are near enough symmetric that the thumb barely moves.
    expect(Cascade.rightwardChance(~seatX=stage.width /. 2. -. 0.5, ~stage))->toBeCloseTo(0.5)
    expect(Cascade.rightwardChance(~seatX=seatX(1), ~stage))->toBeCloseToWithin(0.6, 1)
    expect(Cascade.rightwardChance(~seatX=seatX(2), ~stage))->toBeCloseToWithin(0.4, 1)
  })

  test("leans away from the wall it is near, by the room it has each way", () => {
    // The outer seats. At `inwardBias` 1 the chance *is* the share of the room: the
    // left seat has about a fifth of the table to its left, so about a fifth of its
    // cards go that way.
    expect(Cascade.rightwardChance(~seatX=seatX(0), ~stage))->toBeCloseToWithin(0.78, 2)
    expect(Cascade.rightwardChance(~seatX=seatX(3), ~stage))->toBeCloseToWithin(0.22, 2)
  })

  test("never asks for a chance it can't have, from a seat off the edge", () => {
    // Not reachable from `spreadSeats`, but the integration's seats are the board's and
    // a foundation can sit anywhere; a card already past the left edge has no room that
    // way at all, which is a chance of 1 rather than of more than 1.
    expect(Cascade.rightwardChance(~seatX=-4., ~stage))->toBe(1.)
    expect(Cascade.rightwardChance(~seatX=stage.width +. 4., ~stage))->toBe(0.)
  })

  test("so about a fifth of the left seat's deck leaves over the near wall, not half", () => {
    // The mechanism end to end, counted rather than reasoned about: 200 launches from
    // the leftmost seat, through the real PRNG. Deterministic — the chain is seeded —
    // so the range is slack for the sampling, not for flake.
    let seat = (seatX(0), Cascade.seatTop)
    let card: Deck.card = {suit: Deck.Spades, rank: Deck.Ace}
    let rng = ref(Cards.seedState(11))
    let leftward = ref(0)
    for _ in 1 to 200 {
      let (next, flyer) = Cascade.spawn(rng.contents, ~knobs=Cascade.defaults, ~stage, ~card, ~seat)
      rng := next
      if flyer.vx < 0. {
        leftward := leftward.contents + 1
      }
    }
    expect(leftward.contents > 25 && leftward.contents < 65)->toBe(true)
  })
})

describe("what a won game leaves to fall", () => {
  test("takes the deck off four complete foundations, kings first and aces last", () => {
    let cards = Cascade.foundationOrder(~seed=1)
    let ranks = (~start, ~end) =>
      cards->Array.slice(~start, ~end)->Array.map((card: Deck.card) => card.rank)
    expect(Array.length(cards))->toBe(52)
    // Four to a round — the top card of each pile in turn — and a rank lower every
    // round, all the way down to the aces that went up first.
    expect(ranks(~start=0, ~end=4))->toEqual([Deck.King, Deck.King, Deck.King, Deck.King])
    expect(ranks(~start=4, ~end=8))->toEqual([Deck.Queen, Deck.Queen, Deck.Queen, Deck.Queen])
    expect(ranks(~start=48, ~end=52))->toEqual([Deck.Ace, Deck.Ace, Deck.Ace, Deck.Ace])
  })

  test("deals the whole pack, so no card falls twice and none is left behind", () => {
    let cards = Cascade.foundationOrder(~seed=12)
    let times = card => cards->Array.filter(other => other == card)->Array.length
    expect(Deck.allCards->Array.every(card => times(card) == 1))->toBe(true)
  })

  test("keeps a suit on one foundation, so a card falls from where it sat", () => {
    // `step` seats a card by `mod(index, seats)` and the deal above is round-robin over
    // the same four, which is the whole reason the seats read as foundations: every
    // spade comes off the pile the first spade came off.
    let cards = Cascade.foundationOrder(~seed=3)
    let seat = index => (cards->Array.getUnsafe(mod(index, 4))).suit
    expect(cards->Array.everyWithIndex((card: Deck.card, index) => card.suit == seat(index)))->toBe(
      true,
    )
  })

  test("varies which suit ended up on which foundation, and nothing else", () => {
    // The one thing a finished game varies. Two seeds rather than a claim about all of
    // them, because there are only twenty-four permutations to go round.
    let piles = seed =>
      Cascade.foundationOrder(~seed)
      ->Array.slice(~start=0, ~end=4)
      ->Array.map((card: Deck.card) => card.suit)
    expect(piles(1))->toEqual(piles(1))
    expect(piles(1) == piles(2))->toBe(false)
  })

  test("is what a run deals from when the caller hands it no cards", () => {
    expect(Cascade.make(~seed=6).cards)->toEqual(Cascade.foundationOrder(~seed=6))
  })
})

describe("leaving the stage", () => {
  let stage: Cascade.stage = {width: 10., height: 6., seats: [(5., 0.)]}

  test("retires a card only once the whole of it is past the edge", () => {
    let flyer: Cascade.flyer = {
      card: {suit: Deck.Spades, rank: Deck.Ace},
      x: -0.5,
      y: 0.,
      vx: -1.,
      vy: 0.,
    }
    // Still half on stage, so still drawn: a card that vanished at the edge would
    // blink out with an edge showing.
    expect(Cascade.hasLeft(flyer, ~stage))->toBe(false)
    expect(Cascade.hasLeft({...flyer, x: -1.5}, ~stage))->toBe(true)
    expect(Cascade.hasLeft({...flyer, x: 10.5}, ~stage))->toBe(true)
  })

  test("is done once the last card has gone, and counts what left", () => {
    let two = Deck.allCards->Array.slice(~start=0, ~end=2)
    let run = ref(Cascade.make(~seed=5, ~cards=two))
    let knobs = {...Cascade.defaults, launchMs: 100.}
    for _ in 1 to 2000 {
      run := Cascade.step(run.contents, ~knobs, ~stage, ~dt=1. /. 120.)
    }
    expect(Cascade.isDone(run.contents))->toBe(true)
    expect(run.contents.retired)->toBe(2)
  })
})

describe("the device-pixel snap", () => {
  test("lands a CSS coordinate on a whole device pixel, at any ratio", () => {
    // The half-CSS-pixel grid at 2×, the third at 3×: the snap is in device space, so
    // what it rounds to gets finer as the display does.
    expect(Cascade.snapToDevice(10.3, ~ratio=2.))->toBe(10.5)
    expect(Cascade.snapToDevice(10.3, ~ratio=1.))->toBe(10.)
    expect(Cascade.snapToDevice(10.4, ~ratio=1.5) *. 1.5)->toBe(16.)
  })

  test("which a whole CSS pixel is not, once the ratio is fractional", () => {
    // The reason this exists at all. 10.5 CSS pixels is 15.75 device pixels at 1.5×,
    // and a blit there is resampled on every frame — so rounding in CSS space, which
    // is where the drawing code reads, buys nothing.
    expect(Math.abs(10.5 *. 1.5 -. Math.round(10.5 *. 1.5)) > 0.)->toBe(true)
    expect(Cascade.snapToDevice(10.5, ~ratio=1.5) *. 1.5)->toBe(16.)
  })

  test("leaves a coordinate alone rather than dividing by a zero ratio", () => {
    expect(Cascade.snapToDevice(10.3, ~ratio=0.))->toBe(10.3)
  })
})
