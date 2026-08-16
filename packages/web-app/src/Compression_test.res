// The share link's codec (`Compression`): DEFLATE via the platform's Compression
// Streams API, base64url on top. These pin the three things a share link depends
// on — that a round trip is lossless, that the output is genuinely URL-safe, and
// that bad input comes back as `None` instead of throwing.
//
// The API is a browser built-in rather than a dependency, and Node has carried it
// as a global since v18 — so the `jsdom` environment these tests run in has a real
// `CompressionStream`, not a stub. What passes here is the same code path the
// browser takes.

open Vitest

// A payload with the shape of the real thing: `SaveState`'s JSON is highly
// repetitive (two-character card codes, the same field names per state), which is
// exactly what DEFLATE eats. Built by hand so this file doesn't depend on `core`'s
// encoding staying put.
let sampleJson = {
  let state = `{"piles":[["AS","2H","TD"],["KC","3S"],[],["QH","4D","5C","6S"]],"loose":["7H"]}`
  `{"v":1,"past":[` ++
  Array.make(~length=40, state)->Array.join(",") ++
  `],"present":` ++
  state ++ `,"future":[]}`
}

describe("Compression", () => {
  testAsync("round-trips a string unchanged", async () => {
    let squeezed = (await Compression.compress(sampleJson))->Option.getOrThrow
    expect(await Compression.decompress(squeezed))->toEqual(Some(sampleJson))
  })

  testAsync("round-trips non-ASCII text", async () => {
    // The codec goes through `TextEncoder`/`TextDecoder`, so multi-byte characters
    // have to survive the byte round trip as well as the DEFLATE one.
    let text = `♠♥♦♣ — カード — 🂡`
    let squeezed = (await Compression.compress(text))->Option.getOrThrow
    expect(await Compression.decompress(squeezed))->toEqual(Some(text))
  })

  testAsync("round-trips the empty string", async () => {
    let squeezed = (await Compression.compress(""))->Option.getOrThrow
    expect(await Compression.decompress(squeezed))->toEqual(Some(""))
  })

  testAsync("emits only URL-safe characters", async () => {
    // The whole point of base64url: no `+`, `/` or `=`, so the blob can sit in a URL
    // without percent-encoding — which would re-inflate it and undo the compression.
    let squeezed = (await Compression.compress(sampleJson))->Option.getOrThrow
    expect(squeezed->String.includes("+"))->toBe(false)
    expect(squeezed->String.includes("/"))->toBe(false)
    expect(squeezed->String.includes("="))->toBe(false)
  })

  testAsync("compresses a repetitive payload well below its original size", async () => {
    // Not a precise ratio — that's the compressor's business, not ours — just the
    // guarantee the feature rests on: a long game shrinks by an order of magnitude,
    // so an undo stack fits in a link. Base64 costs 33% back and this still clears it.
    let squeezed = (await Compression.compress(sampleJson))->Option.getOrThrow
    expect(String.length(squeezed) * 10 < String.length(sampleJson))->toBe(true)
  })

  testAsync("a blob that isn't valid base64 decodes to None", async () => {
    expect(await Compression.decompress("!!!! not base64 !!!!"))->toEqual(None)
  })

  testAsync("a truncated blob decodes to None", async () => {
    // The paste-went-wrong case: well-formed base64url, but the DEFLATE stream it
    // carries stops in the middle. Must be a rejected link, not a thrown exception.
    let squeezed = (await Compression.compress(sampleJson))->Option.getOrThrow
    let half = squeezed->String.slice(~start=0, ~end=String.length(squeezed) / 2)
    expect(await Compression.decompress(half))->toEqual(None)
  })

  testAsync("base64 that isn't a DEFLATE stream decodes to None", async () => {
    expect(await Compression.decompress("AAAAAAAAAAAAAAAA"))->toEqual(None)
  })
})
