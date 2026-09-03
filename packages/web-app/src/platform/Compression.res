// Squeeze a string small enough to travel in a URL, and unsqueeze it again, over the
// browser's own **Compression Streams API** (`CompressionStream`/`DecompressionStream`)
// — a platform built-in, so this costs nothing in the bundle and adds no dependency to
// install, lock or keep current. It's what lets a share link (see `ShareLink`) carry a
// whole undo/redo stack.
//
// **The choice of `deflate-raw` over gzip, of base64url over base64, and the size
// arithmetic behind both are documented in `docs/save-and-share.md`.**
//
// Two things a caller plans around: everything here is **async**, and both directions
// answer with an `option` rather than throwing — a browser without the API, a corrupt
// blob, a truncated paste and a link from an older format all mean "no string".
// Whether the platform can do this at all. Baseline in every browser this app
// targets (Chrome 80+, Firefox 113+, Safari 16.4+), so the false branch is a
// courtesy for an old install rather than a case anyone should hit — but it turns
// a hard `TypeError` into a disabled feature, which is the right shape of failure
// for something reached from a debug menu.
let supported: bool = %raw(`
  typeof CompressionStream === "function" && typeof DecompressionStream === "function"
`)

// --- Platform bindings -------------------------------------------------------
// Deliberately local and minimal, in the `WebDom`/`Vitest` mold: just the corners
// of Blob/Streams/Response/TextEncoder this module actually drives.

type uint8Array
type arrayBuffer
type readableStream
type writableStream
type writer
// `CompressionStream` and `DecompressionStream` are both TransformStreams — the
// same shape on both sides, so one type serves both.
type transformStream
type response

@new external makeCompressionStream: string => transformStream = "CompressionStream"
@new external makeDecompressionStream: string => transformStream = "DecompressionStream"

// The bytes go in through the transform's writable end rather than via
// `new Blob([bytes]).stream()`. Both work in a browser, but jsdom's `Blob` has no
// `stream()` — so the Blob route would make this module untestable anywhere but a
// real browser, for no gain. This way is also one object shorter.
@get external writable: transformStream => writableStream = "writable"
@get external readable: transformStream => readableStream = "readable"
@send external getWriter: writableStream => writer = "getWriter"
@send external write: (writer, uint8Array) => promise<unit> = "write"
@send external closeWriter: writer => promise<unit> = "close"

// `Response` is the shortest path from a stream back to bytes: it drains the whole
// stream for us, so this module never hand-rolls a reader loop.
@new external makeResponse: readableStream => response = "Response"
@send external responseArrayBuffer: response => promise<arrayBuffer> = "arrayBuffer"

@new external bytesOfBuffer: arrayBuffer => uint8Array = "Uint8Array"
@new external bytesOfCodes: array<int> => uint8Array = "Uint8Array"
@get external byteLength: uint8Array => int = "length"
@send external subarray: (uint8Array, int, int) => uint8Array = "subarray"

type textEncoder
@new external makeTextEncoder: unit => textEncoder = "TextEncoder"
@send external encodeText: (textEncoder, string) => uint8Array = "encode"

type textDecoder
@new external makeTextDecoder: unit => textDecoder = "TextDecoder"
@send external decodeText: (textDecoder, uint8Array) => string = "decode"

@val external btoa: string => string = "btoa"
@val external atob: string => string = "atob"
@send external charCodeAt: (string, int) => int = "charCodeAt"
// `String.fromCharCode.apply(null, bytes)`: one argument per byte, straight off the
// typed array. `apply` only needs an array-like, where a spread would first copy
// the chunk into a real `array` — and on the one cold call a page makes, that copy
// is most of the cost.
@val @scope(("String", "fromCharCode"))
external charsOfBytes: (@as(json`null`) _, uint8Array) => string = "apply"

// The DEFLATE flavour, named once. See `docs/save-and-share.md` for why it's the bare
// stream and not gzip.
let format = "deflate-raw"

// --- base64url ---------------------------------------------------------------

// How many bytes to turn into characters per `String.fromCharCode` call. The
// `apply` in `charsOfBytes` becomes one JS argument *per byte*, and engines cap
// argument counts somewhere in the tens of thousands — so handing it a whole
// multi-kilobyte game, or a 16KB font face, at once is a `RangeError` waiting for
// the first payload long enough. Chunking keeps every call far below the limit, at
// no meaningful cost.
let chunkSize = 8192

// Bytes → the standard base64 alphabet, via the binary string `btoa` wants. This is
// the app's one encoder: `CardRaster` runs the embedded font faces through it too.
let base64OfBytes = (bytes: uint8Array): string => {
  let length = byteLength(bytes)
  let binary = ref("")
  let offset = ref(0)
  while offset.contents < length {
    let end = offset.contents + chunkSize
    let stop = end > length ? length : end
    binary := binary.contents ++ charsOfBytes(subarray(bytes, offset.contents, stop))
    offset := stop
  }
  btoa(binary.contents)
}

// The URL-safe alphabet (RFC 4648 §5): `+/` → `-_`, and the padding dropped. `=`
// only ever appears as trailing padding in base64 output, so removing every one is
// the same as trimming the tail.
let base64UrlOfBytes = (bytes: uint8Array): string =>
  base64OfBytes(bytes)
  ->String.replaceAll("+", "-")
  ->String.replaceAll("/", "_")
  ->String.replaceAll("=", "")

// …and back. The padding is re-derived rather than stored: base64 encodes three
// bytes per four characters, so the length is rounded up to the next multiple of
// four with `=`. A length that's 1 mod 4 is not valid base64 at all — `atob` will
// reject it, which the caller's `try` turns into `None`.
let bytesOfBase64Url = (encoded: string): uint8Array => {
  let base64 = encoded->String.replaceAll("-", "+")->String.replaceAll("_", "/")
  let remainder = mod(String.length(base64), 4)
  let padded = remainder == 0 ? base64 : base64 ++ String.repeat("=", 4 - remainder)
  let binary = atob(padded)
  let length = String.length(binary)
  let codes = Array.make(~length, 0)
  for index in 0 to length - 1 {
    codes[index] = charCodeAt(binary, index)
  }
  bytesOfCodes(codes)
}

// --- The round trip ----------------------------------------------------------

// Run `bytes` through one of the two transform streams and collect the result.
// The shared middle of `compress`/`decompress` — they differ only in which stream
// they build.
// Deliberately *not* awaited: with a one-chunk high-water mark the write only
// settles once the readable end is drained, which is the `Response` below — so
// awaiting here first would deadlock. Their rejections are swallowed rather than
// left to become unhandled, because the same failure resurfaces on the read side,
// where the caller's `try` is waiting for it.
let pipe = async (bytes: uint8Array, stream: transformStream): uint8Array => {
  let sink = stream->writable->getWriter
  sink->write(bytes)->Promise.catch(_ => Promise.resolve())->ignore
  sink->closeWriter->Promise.catch(_ => Promise.resolve())->ignore
  bytesOfBuffer(await makeResponse(stream->readable)->responseArrayBuffer)
}

// `text` compressed and base64url'd, or `None` if the platform can't (see
// `supported`). The `try` also covers a stream that errors mid-flight — no known
// trigger, but a rejected promise here would otherwise escape into an unhandled
// rejection from a click handler.
let compress = async (text: string): option<string> =>
  if !supported {
    None
  } else {
    try {
      let bytes = makeTextEncoder()->encodeText(text)
      Some(base64UrlOfBytes(await pipe(bytes, makeCompressionStream(format))))
    } catch {
    | _ => None
    }
  }

// The inverse: `None` for anything that isn't a blob this module produced. That
// covers a truncated paste (`atob` throws on a bad length or a stray character), a
// well-formed base64 payload that isn't DEFLATE (the stream rejects), and bytes
// that inflate to something that isn't valid UTF-8. All of them are "this link is
// no good", which is the caller's problem to report, not a crash.
let decompress = async (encoded: string): option<string> =>
  if !supported {
    None
  } else {
    try {
      let bytes = bytesOfBase64Url(encoded)
      Some(makeTextDecoder()->decodeText(await pipe(bytes, makeDecompressionStream(format))))
    } catch {
    | _ => None
    }
  }
