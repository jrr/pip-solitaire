// A QR code for a string, drawn as real SVG rather than a bitmap, so it stays sharp at
// whatever size the panel gives it.
//
// The encoding is `uqr`'s; this module only turns its grid of modules into one `<path>`,
// a run of dark modules per subpath, which keeps a version-40 code to a few thousand
// path commands instead of one element per square.
//
// **Encoding can fail, and the caller has to be told.** A QR code holds about 2,900
// bytes at most, and a game-state link carries the whole undo history, so a long game
// can outgrow it. `matrix` answers `None` for that rather than throwing, and the caller
// decides what goes on screen in its place.

type matrix = {size: int, data: array<array<bool>>}

type options = {ecc: string, border: int}
@module("uqr") external encode: (string, options) => matrix = "encode"

// The standard's own quiet zone, drawn inside the image: a scanner finds the code by
// its light margin, and a dark panel right up against the finder squares is no margin.
let quietZone = 4

// Error correction at its lowest, `L`: the code is read off a lit screen rather than a
// scuffed label, and every level above it spends capacity a long game's link needs.
let matrix = (text: string): option<matrix> =>
  try {
    Some(encode(text, {ecc: "L", border: quietZone}))
  } catch {
  | _ => None
  }

// One `M x y h n v1 h-n z` per horizontal run of dark modules.
let path = ({data}: matrix): string => {
  let commands = []
  data->Array.forEachWithIndex((row, y) => {
    let start = ref(None)
    let close = x =>
      start.contents->Option.forEach(from => {
        let n = Int.toString(x - from)
        commands->Array.push(`M${Int.toString(from)} ${Int.toString(y)}h${n}v1h-${n}z`)
        start := None
      })
    row->Array.forEachWithIndex((dark, x) =>
      if dark {
        if start.contents->Option.isNone {
          start := Some(x)
        }
      } else {
        close(x)
      }
    )
    close(Array.length(row))
  })
  commands->Array.join("")
}

type props = {
  matrix: matrix,
  // What the code says, for a reader that can't scan it.
  label: string,
}

// `crispEdges` so neighbouring runs meet without the hairline seams anti-aliasing
// leaves between them, which a scanner can read as light modules.
let make = ({matrix, label}) => {
  let side = Int.toString(matrix.size)
  <svg
    className="qr-code"
    xmlns="http://www.w3.org/2000/svg"
    viewBox={`0 0 ${side} ${side}`}
    role="img"
    ariaLabel=label
    shapeRendering="crispEdges"
  >
    <rect width=side height=side fill="#fff" />
    <path d={path(matrix)} fill="#000" />
  </svg>
}
