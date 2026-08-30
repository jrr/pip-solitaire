// The debug log's publish/subscribe seam. Neither real
// destination is asserted here — not the JS console, not the in-app panel — because
// both are just subscribers: the tests subscribe their own, which is exactly how
// the panel receives its lines, and check what does (and doesn't) come through.
//
// The gate is derived from the subscribers rather than set, which is what lets the
// instrumentation stay in the shipped code. The scrollback `Ring` is checked here too,
// since it's the piece that bounds a long session's log (the panel that renders it
// needs a browser; see browser-tests/debug-console.spec.mjs).

open Vitest

// Run `body` with a fresh subscriber capturing entries, unsubscribing afterwards so
// nothing leaks into the next test. Hands back both the buffer and the unsubscribe
// thunk, for the tests that want to drop the subscription mid-flight.
let withSubscriber = body => {
  let entries: array<DebugLog.entry> = []
  let unsubscribe = DebugLog.subscribe(entry => entries->Array.push(entry))
  body(entries, unsubscribe)
  unsubscribe()
}

let entry = (~seq=1, ~label, ~value=None, ~spans=None): DebugLog.entry => {
  seq,
  time: 0.,
  label,
  value,
  spans,
}

describe("DebugLog gate", () => {
  test("publishes nothing while nobody is listening", () => {
    // The gate in its shipped state: no subscribers at all.
    expect(DebugLog.enabled())->toBe(false)
    DebugLog.log("dispatch", "x")
    DebugLog.message("undo")
    expect(DebugLog.enabled())->toBe(false)
  })

  test("one entry per interaction reaches a subscriber", () => {
    withSubscriber(
      (entries, _) => {
        expect(DebugLog.enabled())->toBe(true)
        DebugLog.message("undo")
        DebugLog.log("dispatch", "x")
        expect(Array.length(entries))->toBe(2)
      },
    )
  })

  test("unsubscribing closes the gate again", () => {
    withSubscriber(
      (entries, unsubscribe) => {
        DebugLog.message("undo")
        unsubscribe()
        expect(DebugLog.enabled())->toBe(false)
        DebugLog.message("undo")
        expect(Array.length(entries))->toBe(1)
      },
    )
  })

  test("every subscriber sees every entry", () => {
    withSubscriber(
      (first, _) =>
        withSubscriber(
          (second, _) => {
            DebugLog.message("win")
            expect(Array.length(first))->toBe(1)
            expect(Array.length(second))->toBe(1)
          },
        ),
    )
  })
})

describe("DebugLog entries", () => {
  test("an entry carries its label, its value as JSON, and a rising seq", () => {
    withSubscriber(
      (entries, _) => {
        DebugLog.log("result", "accepted")
        DebugLog.message("undo")
        let first = entries->Array.getUnsafe(0)
        let second = entries->Array.getUnsafe(1)
        expect(first.label)->toBe("result")
        expect(first.value)->toEqual(Some(`"accepted"`))
        // A message-only line has no payload — that's what the panel styles (and the
        // console renders) as a bare label.
        expect(second.value)->toEqual(None)
        expect(second.seq)->toBe(first.seq + 1)
      },
    )
  })

  test("a value that can't be stringified logs its label alone", () => {
    withSubscriber(
      (entries, _) => {
        DebugLog.log("dispatch", () => ())
        expect((entries->Array.getUnsafe(0)).value)->toEqual(None)
      },
    )
  })

  test("format renders the value as JSON after its prefixed label", () => {
    expect(
      DebugLog.format(entry(~label="result", ~value=Some(`"accepted"`))),
    )->toBe(`[pip] result "accepted"`)
    expect(DebugLog.format(entry(~label="undo")))->toBe("[pip] undo")
  })
})

// The seam that carries a rendered board to the panel. The property worth pinning
// is *graceful degradation*: spans are additional to the plain text, never instead of it,
// so the subscriber that can paint them does, and every other subscriber — the JS console,
// and any test — keeps showing exactly what it showed before.
describe("DebugLog.line", () => {
  let row: Render.line = [
    {text: "│", ink: Render.Plain},
    {text: `K♥  `, ink: Render.Suit(Rules.Red)},
    {text: "│", ink: Render.Plain},
  ]

  test("publishes the spans and the plain text of the same row", () => {
    withSubscriber(
      (entries, _) => {
        DebugLog.line(row)
        let published = entries->Array.getUnsafe(0)
        expect(published.spans)->toEqual(Some(row))
        // The label is the row flattened — what a subscriber that can't paint shows.
        expect(published.label)->toBe(`│K♥  │`)
        expect(published.value)->toEqual(None)
      },
    )
  })

  // The JS console subscriber is unchanged by any of this: it formats the label and never
  // looks at the spans, so a printed board reads there exactly as it always did.
  test("format ignores the spans and prints the flattened row", () =>
    expect(
      DebugLog.format(entry(~label=`│K♥  │`, ~spans=Some(row))),
    )->toBe(`[pip] │K♥  │`)
  )

  // An ordinary line still carries no spans, so nothing that isn't a rendered row goes
  // down the painted path by accident.
  test("an ordinary message carries no spans", () => {
    withSubscriber(
      (entries, _) => {
        DebugLog.message("undo")
        DebugLog.log("dispatch", "x")
        expect(entries->Array.every(e => e.spans == None))->toBe(true)
      },
    )
  })

  // The gate still holds: a rendered board costs nothing with nobody listening, which
  // matters more here than for a one-line message — `print` publishes ~18 rows.
  test("publishes nothing while nobody is listening", () => {
    expect(DebugLog.enabled())->toBe(false)
    DebugLog.line(row)
    expect(DebugLog.enabled())->toBe(false)
  })
})

describe("DebugLog.Ring", () => {
  test("keeps the newest entries and reports each one it drops", () => {
    let ring = DebugLog.Ring.make(~capacity=3)
    let dropped =
      Array.make(~length=5, 0)->Array.mapWithIndex(
        (_, i) => DebugLog.Ring.push(ring, entry(~seq=i + 1, ~label="line")),
      )
    // Nothing falls off until the ring is full…
    expect(dropped->Array.getUnsafe(0))->toEqual(None)
    expect(dropped->Array.getUnsafe(2))->toEqual(None)
    // …and from then on each push drops exactly one, oldest first — which is what a
    // view holding one node per entry trims by.
    expect(dropped->Array.getUnsafe(3)->Option.map(e => e.seq))->toEqual(Some(1))
    expect(dropped->Array.getUnsafe(4)->Option.map(e => e.seq))->toEqual(Some(2))
    expect(DebugLog.Ring.length(ring))->toBe(3)
    expect(DebugLog.Ring.entries(ring)->Array.map(e => e.seq))->toEqual([3, 4, 5])
  })

  test("the panel's ring is bounded well above a session's visible scrollback", () => {
    let ring = DebugLog.Ring.make(~capacity=DebugConsole.capacity)
    for i in 1 to DebugConsole.capacity + 50 {
      DebugLog.Ring.push(ring, entry(~seq=i, ~label="dispatch"))->ignore
    }
    expect(DebugLog.Ring.length(ring))->toBe(DebugConsole.capacity)
    expect((DebugLog.Ring.entries(ring)->Array.getUnsafe(0)).seq)->toBe(51)
  })
})
