// The "Wiggle Waggle" row, exercised in isolation.
//
// The row's whole shape is decided by `Motion.state`, and the four states don't map
// onto one bool — which is why it isn't a `<MenuToggleRow>` call, and why there is a
// case here per state.
open Vitest
open TestDom

let render = (state, ~onToggle=() => ()) => Html.create(MenuWiggleRow.make({state, onToggle}))

let subtitle = row => row->find(".menu-row__desc")->Option.map(text)

let checked = row => row->attrOr("aria-checked")

let isOn = row => row->classes->String.includes("menu-row--on")

describe("MenuWiggleRow", () => {
  test("is titled, and asks rather than explains, while it's healthy", () => {
    // The other settings say what they do; this one poses the question instead, in
    // both healthy states — the same line whether it's listening or not.
    let off = render(Motion.Off)
    expect(off->find(".menu-row__label")->Option.mapOr("", text))->toBe("Wiggle Waggle")
    expect(off->subtitle)->toBe(Some(MenuWiggleRow.teaser))
    expect(render(Motion.On)->subtitle)->toBe(Some(MenuWiggleRow.teaser))
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
    // The reason displaces the teaser rather than queueing behind it: the two share
    // one line, and a snap-back still asking "what might this do?" reads as a
    // dropped tap.
    expect(blocked->subtitle)->toBe(Motion.subtitle(Motion.Blocked))
    expect(blocked->subtitle == Some(MenuWiggleRow.teaser))->toBe(false)
  })

  test("explains a device or origin it can't even ask on", () => {
    // The subtitle is the only place a reason can surface: the switch itself just
    // reads off, the same as a setting nobody has turned on. So the teaser has to
    // give way to it — a row that only ever asked "what might this do?" would leave
    // an inert switch looking like a working one.
    let states = [Motion.Unavailable(Motion.NoSensor), Motion.Unavailable(Motion.Insecure)]
    states->Array.forEach(
      state => {
        expect(render(state)->subtitle)->toBe(Motion.subtitle(state))
        expect(render(state)->subtitle == Some(MenuWiggleRow.teaser))->toBe(false)
      },
    )
  })

  test("asks to be toggled when tapped", () => {
    let taps = ref(0)
    render(Motion.Off, ~onToggle=() => taps := taps.contents + 1)->click
    expect(taps.contents)->toBe(1)
  })
})
