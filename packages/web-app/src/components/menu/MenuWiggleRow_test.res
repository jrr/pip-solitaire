// The "Wiggle Waggle" row, exercised in isolation now that it's a component
// of its own.
//
// The row's whole shape is decided by `Motion.state`, and the four states don't map
// onto one bool — which is why it isn't a `<MenuToggleRow>` call. What this file
// pins:
//
// 1. **A healthy row says nothing.** Off or listening, there's no description at all
//    — the other settings explain themselves; finding out what this one does is the
//    point. A `desc` element appearing in those states would give the game away.
// 2. **A problem does get a line.** Blocked, no sensor, insecure origin: the subtitle
//    is the only place the reason can surface, since the switch itself just reads off.
// 3. **`Blocked` reads off but keeps its reason.** The OS refused, so the switch has
//    to snap back — but silently snapping back with no line is indistinguishable from
//    a tap that didn't register.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest
open TestDom

let render = (state, ~onToggle=() => ()) => Html.create(MenuWiggleRow.make({state, onToggle}))

let subtitle = row => row->find(".menu-row__desc")->Option.map(text)

let checked = row => row->attrOr("aria-checked")

let isOn = row => row->classes->String.includes("menu-row--on")

describe("MenuWiggleRow", () => {
  test("is titled, and deliberately unexplained, while it's healthy", () => {
    let off = render(Motion.Off)
    expect(off->find(".menu-row__label")->Option.mapOr("", text))->toBe("Wiggle Waggle")
    expect(off->subtitle)->toBe(None)
    expect(render(Motion.On)->subtitle)->toBe(None)
  })

  test("reads on only while it's actually listening", () => {
    expect(render(Motion.Off)->isOn)->toBe(false)
    expect(render(Motion.Off)->checked)->toBe("false")
    expect(render(Motion.On)->isOn)->toBe(true)
    expect(render(Motion.On)->checked)->toBe("true")
  })

  test("snaps back to off when the OS refuses — but says why", () => {
    let blocked = render(Motion.Blocked)
    expect(blocked->isOn)->toBe(false)
    expect(blocked->subtitle)->toBe(Motion.subtitle(Motion.Blocked))
    // The reason has to be *something*, or the snap-back reads as a dropped tap.
    expect(blocked->subtitle->Option.isSome)->toBe(true)
  })

  test("explains a device or origin it can't even ask on", () => {
    expect(render(Motion.Unavailable(Motion.NoSensor))->subtitle->Option.isSome)->toBe(true)
    expect(render(Motion.Unavailable(Motion.Insecure))->subtitle->Option.isSome)->toBe(true)
  })

  test("asks to be toggled when tapped", () => {
    let taps = ref(0)
    render(Motion.Off, ~onToggle=() => taps := taps.contents + 1)->click
    expect(taps.contents)->toBe(1)
  })
})
