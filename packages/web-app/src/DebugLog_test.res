// The debug log's publish/subscribe seam (#213, reshaped by #271). Neither real
// destination is asserted here — not the JS console, not the in-app panel — because
// both are just subscribers now: the tests subscribe their own, which is exactly how
// the panel receives its lines, and check what does (and doesn't) come through.
//
// The property worth pinning is the *derived gate*: with nobody listening, a `log`
// costs nothing at all, which is what lets the instrumentation stay in the shipped
// code. The scrollback `Ring` is checked here too, since it's the piece that bounds a
// long session's log (the panel that renders it needs a browser; see
// browser-tests/debug-console.spec.mjs).

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

let entry = (~seq=1, ~label, ~value=None): DebugLog.entry => {seq, time: 0., label, value}

describe("DebugLog gate (#213)", () => {
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

describe("DebugLog entries (#271)", () => {
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

describe("DebugLog.Ring (#271)", () => {
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
