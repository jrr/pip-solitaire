// The tier a load settles on, read off a navigator the test stands in for, and what a
// solve that never finished leaves for the next load — jsdom's `localStorage` is real
// enough for both halves.
open Vitest

@val @scope("localStorage") external clear: unit => unit = "clear"
@val @scope("localStorage") external getItem: string => Nullable.t<string> = "getItem"

let iPhone = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
let iPad = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"
let windows = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0"

describe("Device.tierOf", () => {
  test("deviceMemory decides where a browser gives it, and 8 — its cap — is large", () => {
    let tierOf = gb => Device.tierOf(~deviceMemory=Some(gb), ~userAgent=iPhone, ~maxTouchPoints=5)
    expect(tierOf(2.))->toEqual(Solver.Small)
    expect(tierOf(4.))->toEqual(Solver.Medium)
    expect(tierOf(8.))->toEqual(Solver.Large)
  })

  test("without it, an iPhone and an iPad — which says it is a Mac — are small", () => {
    expect(Device.tierOf(~deviceMemory=None, ~userAgent=iPhone, ~maxTouchPoints=5))->toEqual(
      Solver.Small,
    )
    expect(Device.tierOf(~deviceMemory=None, ~userAgent=iPad, ~maxTouchPoints=5))->toEqual(
      Solver.Small,
    )
  })

  test("a Mac with no touch, and anything else with no figure, is medium", () => {
    expect(Device.tierOf(~deviceMemory=None, ~userAgent=iPad, ~maxTouchPoints=0))->toEqual(
      Solver.Medium,
    )
    expect(Device.tierOf(~deviceMemory=None, ~userAgent=windows, ~maxTouchPoints=10))->toEqual(
      Solver.Medium,
    )
  })
})

describe("Device.recover", () => {
  test("a load after a solve that finished changes nothing", () => {
    clear()
    Device.started()
    Device.ended()
    expect(Device.recover(~memory=None))->toEqual((None, None))
    expect(Device.ceiling())->toEqual(None)
  })

  test("a solve that never finished lowers the device's tier, persistently and once", () => {
    clear()
    let before = Device.tier(~memory=None)
    Device.started()
    let (memory, dropped) = Device.recover(~memory=None)
    expect(memory)->toEqual(None)
    expect(dropped)->toEqual(Some({Device.from: before, to: Solver.lower(before)}))
    expect(Device.tier(~memory=None))->toEqual(Solver.lower(before))
    // Said once: the mark is gone, and the ceiling it left stays.
    expect(Device.recover(~memory=None))->toEqual((None, None))
    expect(Device.tier(~memory=None))->toEqual(Solver.lower(before))
    expect(getItem(Device.solvingKey)->Nullable.toOption)->toEqual(None)
  })

  test("a tier the setting chose is the one lowered, and the ceiling is left alone", () => {
    clear()
    Device.started()
    expect(Device.recover(~memory=Some(Solver.Large)))->toEqual((
      Some(Solver.Medium),
      Some({Device.from: Solver.Large, to: Solver.Medium}),
    ))
    expect(Device.ceiling())->toEqual(None)
  })

  test("the setting outranks a ceiling, and small is the floor", () => {
    clear()
    Device.started()
    let _ = Device.recover(~memory=Some(Solver.Small))
    expect(Device.tier(~memory=Some(Solver.Large)))->toEqual(Solver.Large)
    Device.started()
    expect(Device.recover(~memory=Some(Solver.Small)))->toEqual((
      Some(Solver.Small),
      Some({Device.from: Solver.Small, to: Solver.Small}),
    ))
  })
})

describe("Device.say", () => {
  test("names both tiers and the way to choose, or says it is already at the floor", () => {
    let lowered = Device.say({from: Solver.Medium, to: Solver.Small})
    expect(lowered->String.includes("small rather than medium"))->toBe(true)
    expect(lowered->String.includes("set memory"))->toBe(true)
    expect(Device.say({from: Solver.Small, to: Solver.Small})->String.includes("already"))->toBe(
      true,
    )
  })
})
