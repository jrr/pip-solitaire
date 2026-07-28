// The Wiggle Waggle switch's pure helpers (#235): the state → is-it-on mapping and
// the problem-only subtitle. These are what the Settings row renders, so they're
// worth pinning without a device — the capability/permission side (`requestAccess`,
// the subscription) needs a real sensor and secure origin and is verified on a phone.

open Vitest

describe("Motion switch state (#235)", () => {
  test("only the listening state reads as on", () => {
    expect(Motion.isOn(Motion.On))->toBe(true)
    expect(Motion.isOn(Motion.Off))->toBe(false)
    // Blocked snaps the switch *back* to off while still carrying its subtitle.
    expect(Motion.isOn(Motion.Blocked))->toBe(false)
    expect(Motion.isOn(Motion.Unavailable(NoSensor)))->toBe(false)
    expect(Motion.isOn(Motion.Unavailable(Insecure)))->toBe(false)
  })

  test("a healthy switch shows no subtitle", () => {
    // The row is title-only when off or listening — a present subtitle always means
    // there's a problem to report.
    expect(Motion.subtitle(Motion.Off))->toEqual(None)
    expect(Motion.subtitle(Motion.On))->toEqual(None)
  })

  test("each problem state carries its own explanation", () => {
    expect(Motion.subtitle(Motion.Blocked))->toEqual(
      Some(
        "Motion access is off. Turn it on in Settings → Safari → Motion & Orientation Access.",
      ),
    )
    expect(Motion.subtitle(Motion.Unavailable(NoSensor)))->toEqual(
      Some("This device doesn't report motion."),
    )
    expect(Motion.subtitle(Motion.Unavailable(Insecure)))->toEqual(
      Some("Needs a secure (https) connection."),
    )
  })
})
