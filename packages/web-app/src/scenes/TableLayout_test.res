// The card table's fits, checked without a browser. The geometry itself is
// `docs/board-geometry.md`.
//
// These are the claims answerable from arithmetic alone: which of the two fits binds
// and when, that the clamp holds at both ends, that `minStageWidth` really is the width
// fit solved for the floor (which is the thing `ConsoleDock`'s refusal leans on), that
// the published CSS variables keep the proportions the stylesheet doesn't restate, and
// that the drop hit-test is strict across and generous down.
//
// `browser-tests/geometry.spec.mjs` is the other half — that these numbers land real
// cards in the right pixels, measured off a real engine. What it shouldn't have to be
// is the first place a divide-by-zero or an inverted clamp is noticed.
//
// The numbers are stated as the layout's own constants wherever the claim is about a
// relationship (`minScale`, `maxScale`, `minStageWidth`), and as plain pixel sizes where
// the claim is about a device — a desktop stage, a phone in landscape — so a reader can
// tell which assertions would have to change if a footprint were retuned.

open Vitest

// A FreeCell board: eight cascades across the busiest row, laid out in two rows (the
// free cells and foundations above, the cascades below), with the opening deal's
// deepest pile at seven cards plus `fanHeadroom` of room to grow.
let columns = 8
let rows = 2
let freecellFan = TableLayout.fanExtent(
  ~hasFanned=true,
  ~referenceDepth=7 + TableLayout.fanHeadroom,
)

// The fit, for a stage of the given size, with the rows' fixed vertical offset held at
// a typical 8px so the cases below differ only in what they mean to differ in.
let fit = (~w, ~h, ~fanExtent=freecellFan, ~widestRow=columns, ~rowsCount=rows) =>
  TableLayout.scaleFor(~avail=w, ~availH=h, ~vFixed=8., ~widestRow, ~rowsCount, ~fanExtent)

describe("TableLayout — the fits", () => {
  test("a stage with nothing to divide by yields no scale at all", () => {
    // Not a fallback number: the caller keeps the scale it had. A playfield measures 0
    // wide before it has been laid out and again mid-resize on some engines, and a
    // board that snapped to `minScale` for one frame each time would be visible.
    expect(fit(~w=0., ~h=800.))->toEqual(None)
    expect(fit(~w=-10., ~h=800.))->toEqual(None)
    expect(fit(~w=1200., ~h=800., ~widestRow=0))->toEqual(None)
  })

  test("a board with no piles to lay out is the same non-answer", () => {
    // `widestRow` is 0 for a game that declares no piles; dividing by it would give
    // Infinity, which the clamp would then happily hand back as `maxScale`.
    expect(fit(~w=1200., ~h=800., ~widestRow=0))->toEqual(None)
  })

  test("a huge stage stops at the ceiling", () => {
    // Both fits are slack, so the clamp is the only thing left deciding.
    expect(fit(~w=100_000., ~h=100_000.))->toEqual(Some(TableLayout.maxScale))
  })

  test("a tiny stage stops at the floor", () => {
    // Below the floor the cards clamp rather than shrinking away — the board overflows
    // instead, which is what `ConsoleDock`'s refusal exists to keep off the screen.
    expect(fit(~w=50., ~h=50.))->toEqual(Some(TableLayout.minScale))
  })

  test("the narrowest stage the width fit allows is exactly the floor", () => {
    // The round trip that `minStageWidth` claims: it is the width target solved for
    // `minScale`, so feeding it back in has to land there. Height held generous so the
    // width term is the one that binds. This is the arithmetic `ConsoleDock` refuses a
    // dock on, and the reason neither side names a pixel breakpoint.
    let atFloor = fit(~w=TableLayout.minStageWidth(~columns), ~h=100_000.)
    switch atFloor {
    | Some(scale) => expect(scale)->toBeCloseToWithin(TableLayout.minScale, 6)
    | None => expect("a scale")->toBe("no scale")
    }
  })

  test("a hair under that width is already clamping", () => {
    // Just below, the width target has fallen through the floor and the clamp is
    // holding it up — which is the state the refusal keeps a docked board out of.
    expect(fit(~w=TableLayout.minStageWidth(~columns) -. 20., ~h=100_000.))->toEqual(
      Some(TableLayout.minScale),
    )
  })

  test("height binds on a short screen, width on a narrow one", () => {
    // A landscape phone: plenty wide for eight columns, far too short for a fan of
    // twelve. A portrait one is the other way round. Neither should reach the ceiling,
    // and each should be limited by the axis it is actually short of — checked by
    // moving *only* that axis and watching the scale follow.
    let short = fit(~w=1600., ~h=390.)
    let shorter = fit(~w=1600., ~h=300.)
    let narrow = fit(~w=390., ~h=1600.)
    let narrower = fit(~w=320., ~h=1600.)
    switch (short, shorter, narrow, narrower) {
    | (Some(short), Some(shorter), Some(narrow), Some(narrower)) =>
      expect(short < TableLayout.maxScale)->toBe(true)
      expect(shorter < short)->toBe(true)
      expect(narrow < TableLayout.maxScale)->toBe(true)
      expect(narrower < narrow)->toBe(true)
      // …and the axis it is *not* short of doesn't move it: a taller landscape phone
      // is still height-bound at the same scale until the width term takes over.
      expect(fit(~w=2400., ~h=390.))->toEqual(Some(short))
    | _ => expect("four scales")->toBe("fewer")
    }
  })

  test("a deeper fan shrinks the cards on a screen that is height-bound", () => {
    // The fan is why the height fit exists: sizing to the opening deal alone would
    // overflow the moment a cascade grew, so `fanHeadroom` is built into the extent
    // this is given. More depth, less card.
    let deep = fit(
      ~w=1600.,
      ~h=390.,
      ~fanExtent=TableLayout.fanExtent(~hasFanned=true, ~referenceDepth=20),
    )
    switch (deep, fit(~w=1600., ~h=390.)) {
    | (Some(deep), Some(shallow)) => expect(deep < shallow)->toBe(true)
    | _ => expect("two scales")->toBe("fewer")
    }
  })

  test("a board with no fanned pile grows no fan", () => {
    // Every pile Squared — a gallery or a foundations-only demo. Nothing stacks
    // downward, so the height budget is the row boxes and nothing else, and the depth
    // it would have fanned to is irrelevant.
    expect(TableLayout.fanExtent(~hasFanned=false, ~referenceDepth=20))->toBe(0.)
    expect(TableLayout.fanExtent(~hasFanned=false, ~referenceDepth=0))->toBe(0.)
  })

  test("a single-row board gets the height a second row would have taken", () => {
    // `rowsCount` is the other term in the vertical budget: one row of zones instead of
    // two leaves more of a short screen for the cards themselves.
    switch (fit(~w=1600., ~h=390., ~rowsCount=1), fit(~w=1600., ~h=390.)) {
    | (Some(one), Some(two)) => expect(one > two)->toBe(true)
    | _ => expect("two scales")->toBe("fewer")
    }
  })
})

describe("TableLayout — docking", () => {
  // `ConsoleDock.width` is 340; the stages are real device widths.
  let dock = 340.

  test("a desktop window has room for the dock; a phone has not", () => {
    // The same claim `ConsoleDock_test` makes from the chrome's side, in the layout's
    // own terms.
    expect(TableLayout.fitsDock(~stage=1440., ~cutaway=0., ~inset=dock, ~columns))->toBe(true)
    expect(TableLayout.fitsDock(~stage=390., ~cutaway=0., ~inset=dock, ~columns))->toBe(false)
  })

  test("a landscape phone clears the width floor, and is kept out some other way", () => {
    // Worth pinning because it reads like a bug and isn't: 844px across is wide enough
    // on paper to give up the dock and still deal eight columns above `minScale`. This
    // test is the *width* term and says nothing about the height term that actually
    // binds there — a landscape phone has nothing worth docking beside, and stays out
    // of it by the console being keyboard-only rather than by being refused here.
    expect(TableLayout.fitsDock(~stage=844., ~cutaway=100., ~inset=dock, ~columns))->toBe(true)
  })

  test("the display cutaway comes off the stage before the dock is considered", () => {
    // The safe-area insets `.drop-rows` is pinned inside are stage the board
    // never had, so a window that would just fit the dock stops fitting it once a
    // cutout takes its share.
    expect(TableLayout.fitsDock(~stage=700., ~cutaway=0., ~inset=dock, ~columns))->toBe(true)
    expect(TableLayout.fitsDock(~stage=700., ~cutaway=100., ~inset=dock, ~columns))->toBe(false)
  })

  test("a board of two piles gives up width a FreeCell board cannot", () => {
    // Why the test takes the board's busiest row rather than a constant eight.
    expect(TableLayout.fitsDock(~stage=600., ~cutaway=0., ~inset=dock, ~columns))->toBe(false)
    expect(TableLayout.fitsDock(~stage=600., ~cutaway=0., ~inset=dock, ~columns=2))->toBe(true)
  })
})

describe("TableLayout — the published footprints", () => {
  // What the stylesheet reads. The point of publishing these rather than writing
  // `calc()` ratios in CSS is that the proportions are stated once in ReScript; these
  // check the proportions actually survive the multiplication.
  let varsAt = scale => {
    let table = Dict.fromArray(TableLayout.cssVars(~scale, ~widestRow=columns))
    name => table->Dict.get(name)->Option.getOr(Float.Constants.nan)
  }

  test("the card box keeps the art's own aspect ratio", () => {
    let v = varsAt(0.73)
    expect(v("--card-h") /. v("--card-w"))->toBeCloseToWithin(CardArt.aspect, 10)
  })

  test("the zone box is the card plus a uniform inset on every side", () => {
    // Equal breathing room all the way round, rather than a hand-picked box with a
    // wider top gap than side gap.
    let v = varsAt(0.73)
    expect(v("--zone-w") -. v("--card-w"))->toBeCloseToWithin(
      2. *. TableLayout.zoneInset *. 0.73,
      10,
    )
    expect(v("--zone-h") -. v("--card-h"))->toBeCloseToWithin(
      2. *. TableLayout.zoneInset *. 0.73,
      10,
    )
  })

  test("the zone's corner is concentric with the card's", () => {
    // The frame sits `zoneInset` outside the slot on every side, so its radius has to
    // be the slot's plus that inset for the two corners to share a centre.
    let v = varsAt(0.73)
    expect(v("--zone-radius") -. v("--card-radius"))->toBeCloseToWithin(
      TableLayout.zoneInset *. 0.73,
      10,
    )
  })

  test("every footprint scales linearly, so doubling the scale doubles the board", () => {
    // The property that lets one number drive the whole layout: nothing published here
    // has a fixed term hiding in it.
    let one = varsAt(1.)
    let two = varsAt(2.)
    [
      "--card-w",
      "--card-h",
      "--card-radius",
      "--zone-w",
      "--zone-h",
      "--zone-radius",
      "--rows-max-w",
    ]->Array.forEach(name => expect(two(name))->toBeCloseToWithin(one(name) *. 2., 10))
  })

  test("the row cap is the columns plus the gaps around and between them", () => {
    // Eight zones and nine gaps — the point past which extra stage width becomes
    // equal left/right margins instead of ever-wider column gaps.
    expect(TableLayout.rowsMaxWidth(~widestRow=columns))->toBeCloseToWithin(
      Int.toFloat(columns) *. TableLayout.zoneWidth +.
        Int.toFloat(columns + 1) *. TableLayout.maxColumnGap,
      10,
    )
  })
})

describe("TableLayout — the drop hit-test", () => {
  let zone: TableLayout.rect = {left: 100., top: 100., width: 88., height: 124.}
  let card = (~left, ~top): TableLayout.rect => {left, top, width: 80., height: 112.}

  test("a card centred over the zone hits it", () => {
    expect(TableLayout.hits(~card=card(~left=104., ~top=106.), ~zone))->toBe(true)
  })

  test("horizontally it's the card's centre, not its edge", () => {
    // Strict across, so tightly packed columns stay distinguishable: a card overlapping
    // the zone by most of its width still misses while its centre is outside.
    expect(TableLayout.hits(~card=card(~left=45., ~top=106.), ~zone))->toBe(false)
    expect(TableLayout.hits(~card=card(~left=61., ~top=106.), ~zone))->toBe(true)
    expect(TableLayout.hits(~card=card(~left=188., ~top=106.), ~zone))->toBe(false)
  })

  test("vertically any overlap at all counts", () => {
    // Generous down, so a card need only graze a zone's top or bottom to land in it.
    expect(TableLayout.hits(~card=card(~left=104., ~top=-11.), ~zone))->toBe(true)
    expect(TableLayout.hits(~card=card(~left=104., ~top=223.), ~zone))->toBe(true)
  })

  test("a card clear above or below the zone misses it", () => {
    expect(TableLayout.hits(~card=card(~left=104., ~top=-13.), ~zone))->toBe(false)
    expect(TableLayout.hits(~card=card(~left=104., ~top=225.), ~zone))->toBe(false)
  })
})
