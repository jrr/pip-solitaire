// The cascade's motion, checked where it lives: in card-widths and seconds, with no canvas
// and no clock. Worth pinning here because the way this class of bug arrives is a cascade
// that still looks like a cascade. The pixels are `browser-tests/cascade.spec.mjs`'s.

open Vitest

// No floor and no sides worth reaching, for the cases that want gravity and nothing else.
let openStage: Cascade.stage = {width: 1000., height: 1000., seats: [(0., 0.)]}

// Straight down, and 52 identical cards: no horizontal draw, and no spread, so every card
// is the one the knobs describe.
let dropping = {
  ...Cascade.defaults,
  speed: 0.,
  speedVariance: 0.,
  bouncinessVariance: 0.,
}

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
    // A per-frame constant would put these a factor of two apart; what is left is Euler's
    // own step error, a tenth of a card-width against the thirteen they both fall.
    expect(first(at60).y)->toBeCloseToWithin(first(at120).y, 0)
    expect(first(at120).y > 12.)->toBe(true)
  })

  test("clamps the step, so a tab coming back from the background can't teleport", () => {
    // Ten seconds of arrears in one call: unclamped, that is 1300 card-widths down.
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
    // A card moving faster than the stage is tall, in one step.
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
    // Higher `y` is lower on the stage. The first three only: a card that has all but
    // stopped bouncing tops out a hair above the floor every time.
    expect(Array.length(apexes) >= 3)->toBe(true)
    expect(apexes->Array.getUnsafe(0) < apexes->Array.getUnsafe(1))->toBe(true)
    expect(apexes->Array.getUnsafe(1) < apexes->Array.getUnsafe(2))->toBe(true)
  })

  test("keeps nothing at all at zero bounciness — the card just lands", () => {
    let dead = {...dropping, bounciness: 0.}
    let run = runFor(~knobs=dead, ~stage, ~seconds=3., ~dt=1. /. 120.)
    expect(first(run).y)->toBe(Cascade.floorOf(stage))
    // `Math.abs` because negating a positive speed gives a signed zero.
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
    // The claim the units exist for, and the one a gravity in px/s² breaks.
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
    // Each seat centred on its share of the width.
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
    // Nothing is thrown upwards, which is what keeps 52 launches reading as one cascade.
    expect(flyer.vy)->toBe(0.)
    let speed = Math.abs(flyer.vx)
    let {speed: centre, speedVariance: spread} = Cascade.defaults
    expect(speed >= centre -. spread && speed <= centre +. spread)->toBe(true)
  })
})

describe("a knob and its ±", () => {
  let stage = Cascade.stageOf(~cssWidth=1056., ~cssHeight=560., ~cardWidth=90.)
  let card: Deck.card = {suit: Deck.Spades, rank: Deck.Ace}

  // Fifty-two launches from the middle seat, which is what a run actually draws.
  let deal = knobs => {
    let rng = ref(Cards.seedState(3))
    Array.fromInitializer(~length=52, _ => {
      let (next, flyer) = Cascade.spawn(
        rng.contents,
        ~knobs,
        ~stage,
        ~card,
        ~seat=(stage.width /. 2., Cascade.seatTop),
      )
      rng := next
      flyer
    })
  }

  let span = values => (
    values->Array.reduce(Float.Constants.positiveInfinity, Math.min),
    values->Array.reduce(Float.Constants.negativeInfinity, Math.max),
  )

  test("scatters the deck across the band, and fills it", () => {
    let knobs = {...Cascade.defaults, speed: 5., speedVariance: 1.}
    let (slowest, fastest) = deal(knobs)->Array.map(flyer => Math.abs(flyer.vx))->span
    expect(slowest >= 4.)->toBe(true)
    expect(fastest <= 6.)->toBe(true)
    // …and uses the band rather than hugging its middle.
    expect(slowest < 4.1)->toBe(true)
    expect(fastest > 5.9)->toBe(true)
  })

  test("is 52 identical cards at a spread of zero, which is what the spread is against", () => {
    let knobs = {...Cascade.defaults, speed: 5., speedVariance: 0., bouncinessVariance: 0.}
    let (slowest, fastest) = deal(knobs)->Array.map(flyer => Math.abs(flyer.vx))->span
    expect(slowest)->toBe(5.)
    expect(fastest)->toBe(5.)
  })

  test("gives every card its own bounciness, and keeps it inside 0 and 1", () => {
    // A spread wider than its value, which the sliders reach: a card that keeps more than
    // it landed with never comes down.
    let knobs = {...Cascade.defaults, bounciness: 0.9, bouncinessVariance: 0.4}
    let (dullest, springiest) = deal(knobs)->Array.map(flyer => flyer.bounciness)->span
    expect(dullest >= 0.5)->toBe(true)
    expect(springiest <= 1.)->toBe(true)
    expect(springiest > 0.99)->toBe(true) // the clamp is doing the work, not the draw
  })

  test("and a card keeps the bounciness it launched with, floor after floor", () => {
    // One card, thrown at nothing sideways, on a stage it never leaves: it bounces in
    // place for seven seconds and is the same card throughout. A deck would not answer
    // this — the card at the front of `flying` changes as cards retire.
    let stage: Cascade.stage = {width: 40., height: 8., seats: [(20., 0.)]}
    let knobs = {...Cascade.defaults, speed: 0., speedVariance: 0.}
    let run = ref(Cascade.make(~seed=2, ~cards=[card]))
    let bouncinesses = []
    let landings = ref(0)
    for _ in 1 to 900 {
      let before = run.contents.flying->Array.get(0)->Option.map(flyer => flyer.vy)
      run := Cascade.step(run.contents, ~knobs, ~stage, ~dt=1. /. 120.)
      run.contents.flying
      ->Array.get(0)
      ->Option.forEach(
        flyer => {
          bouncinesses->Array.push(flyer.bounciness)
          if before->Option.getOr(0.) > 0. && flyer.vy < 0. {
            landings := landings.contents + 1
          }
        },
      )
    }
    expect(Array.length(bouncinesses))->toBe(900)
    expect(landings.contents >= 3)->toBe(true) // it really did bounce, several times
    let (lowest, highest) = span(bouncinesses)
    expect(lowest)->toBe(highest)
  })
})

describe("which way a card is thrown", () => {
  // Eleven and a bit card-widths across, which is a desktop stage at a 90px card.
  let stage = Cascade.stageOf(~cssWidth=1056., ~cssHeight=560., ~cardWidth=90.)
  let seatX = index => stage.seats->Array.getUnsafe(index)->fst

  test("is an even coin from a seat with the same room either way", () => {
    // The middle, and the two inner seats, which are near enough symmetric.
    expect(Cascade.rightwardChance(~seatX=stage.width /. 2. -. 0.5, ~stage))->toBeCloseTo(0.5)
    expect(Cascade.rightwardChance(~seatX=seatX(1), ~stage))->toBeCloseToWithin(0.6, 1)
    expect(Cascade.rightwardChance(~seatX=seatX(2), ~stage))->toBeCloseToWithin(0.4, 1)
  })

  test("leans away from the wall it is near, by the room it has each way", () => {
    // At `inwardBias` 1 the chance *is* the share of the room, and the left seat has
    // about a fifth of the table to its left.
    expect(Cascade.rightwardChance(~seatX=seatX(0), ~stage))->toBeCloseToWithin(0.78, 2)
    expect(Cascade.rightwardChance(~seatX=seatX(3), ~stage))->toBeCloseToWithin(0.22, 2)
  })

  test("never asks for a chance it can't have, from a seat off the edge", () => {
    // Not reachable from `spreadSeats`, but a board hands over seats of its own and a
    // foundation can sit anywhere.
    expect(Cascade.rightwardChance(~seatX=-4., ~stage))->toBe(1.)
    expect(Cascade.rightwardChance(~seatX=stage.width +. 4., ~stage))->toBe(0.)
  })

  test("so about a fifth of the left seat's deck leaves over the near wall, not half", () => {
    // Counted rather than reasoned about, through the real PRNG. The chain is seeded, so
    // the slack is for the sampling, not for flake.
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
    // `step` seats by `mod(index, seats)` over the same four, which is what makes a seat
    // read as a foundation.
    let cards = Cascade.foundationOrder(~seed=3)
    let seat = index => (cards->Array.getUnsafe(mod(index, 4))).suit
    expect(cards->Array.everyWithIndex((card: Deck.card, index) => card.suit == seat(index)))->toBe(
      true,
    )
  })

  test("varies which suit ended up on which foundation, and nothing else", () => {
    // Two seeds rather than a claim about all of them: there are only 24 permutations.
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
      bounciness: 0.5,
    }
    // Still half on stage, so still drawn.
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
    // In device space, so what it rounds to gets finer as the display does.
    expect(Cascade.snapToDevice(10.3, ~ratio=2.))->toBe(10.5)
    expect(Cascade.snapToDevice(10.3, ~ratio=1.))->toBe(10.)
    expect(Cascade.snapToDevice(10.4, ~ratio=1.5) *. 1.5)->toBe(16.)
  })

  test("which a whole CSS pixel is not, once the ratio is fractional", () => {
    // The reason it exists: 10.5 CSS pixels is 15.75 device pixels at 1.5×, so rounding
    // in CSS space — where the drawing code reads — buys nothing.
    expect(Math.abs(10.5 *. 1.5 -. Math.round(10.5 *. 1.5)) > 0.)->toBe(true)
    expect(Cascade.snapToDevice(10.5, ~ratio=1.5) *. 1.5)->toBe(16.)
  })

  test("leaves a coordinate alone rather than dividing by a zero ratio", () => {
    expect(Cascade.snapToDevice(10.3, ~ratio=0.))->toBe(10.3)
  })
})
