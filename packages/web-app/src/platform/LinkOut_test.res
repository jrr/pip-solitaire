// The two answers `LinkOut` gives, which is worth pinning precisely because one of them
// reads backwards: the case that wants the reader *out* of the app is the case that asks
// for nothing. Why that is, is in `LinkOut` — what's here is that both cases still come
// out of it, so a tidy-up that "simplifies" the option away has a test to fail.
open Vitest

// The iOS Home Screen web app, as far as this module can tell one: `navigator.standalone`
// is the flag, and jsdom's navigator has no such property until one is defined on it.
let withHomeScreenApp: (unit => unit) => unit = %raw(`(body) => {
  Object.defineProperty(globalThis.navigator, "standalone", {
    value: true,
    configurable: true,
  })
  try {
    body()
  } finally {
    delete globalThis.navigator.standalone
  }
}`)

describe("LinkOut.target", () => {
  test("asks for a tab of its own in a browser, where a navigation costs the board", () => {
    expect(LinkOut.target())->toEqual(Some("_blank"))
  })

  test("asks for nothing in an iOS Home Screen web app, which is what hands it to Safari", () => {
    withHomeScreenApp(() => expect(LinkOut.target())->toEqual(None))
  })

  test("reads the platform per call, so neither answer is decided at load", () => {
    withHomeScreenApp(() => ())
    expect(LinkOut.target())->toEqual(Some("_blank"))
  })
})
