// The debug console log's gate and formatting (#213). The console side-effect itself
// isn't asserted — instead the tests point `DebugLog.sink` at a buffer, so they can
// check exactly which interactions produce a line and that the `enabled` gate
// silences them all when off.

open Vitest

// Run `body` with the log sink capturing into a fresh buffer, restoring the real
// (console) sink and disabling logging afterwards so nothing leaks between tests.
let withCapture = body => {
  let lines = []
  let saved = DebugLog.sink.contents
  DebugLog.sink := (line => lines->Array.push(line))
  body(lines)
  DebugLog.sink := saved
  DebugLog.setEnabled(false)
}

describe("DebugLog gate (#213)", () => {
  test("logs nothing while disabled", () => {
    withCapture(
      lines => {
        DebugLog.setEnabled(false)
        DebugLog.log("dispatch", "x")
        DebugLog.message("undo")
        expect(Array.length(lines))->toBe(0)
      },
    )
  })

  test("logs one prefixed line per interaction once enabled", () => {
    withCapture(
      lines => {
        DebugLog.setEnabled(true)
        DebugLog.message("undo")
        DebugLog.log("dispatch", "x")
        expect(Array.length(lines))->toBe(2)
        expect(lines->Array.getUnsafe(0))->toBe("[pip] undo")
      },
    )
  })

  test("format renders the value as JSON after its prefixed label", () => {
    expect(DebugLog.format("result", "accepted"))->toBe(`[pip] result "accepted"`)
  })
})
