// `mise run comment-census` — how much of this repo is comments, as a number.
//
//   mise run comment-census                 # the table, at HEAD
//   mise run comment-census -- --json       # the same data, machine-readable
//   mise run comment-census -- --rev <ref>  # any commit, for a before/after
//   mise run comment-census -- --help       # the counting rules, in full
//
// It gates nothing. It exists because the first two comment audits were both
// hand-rolled, and the second one happened largely because nothing showed that
// volume had crept back after the first.
//
// Two things a hand-rolled audit gets wrong, and this cannot:
//
//   - It reads `git ls-tree`, never the filesystem. `packages/*/lib/` and
//     `packages/cli/dist/` appear as soon as anything is built and hold whole
//     copies of the sources, so a `find` over `packages/` after a build counts
//     the same line two or three times.
//   - It applies exactly one definition of "comment line". "Lines *containing*
//     a comment" and "lines *beginning* with a comment marker" differ by ~165
//     lines repo-wide; quoting one as a before and the other as an after
//     overstated a saving by more than double.
//
// Deliberately not a threshold. A build that fails at 30.1% invites the
// cheapest possible fix, which is deleting the load-bearing comments along with
// the rest — backwards from what the audits were for, and it would score
// writing `docs/board-driver.md` as neutral at best. If a gate is ever wanted,
// the honest one is a ratchet: fail only when a number goes *up*.
//
// Three commits pin the definition. Change how this file counts and these move,
// which is the signal that the change is wrong:
//
//   mise run comment-census -- --rev 274226e   →  11,707
//   mise run comment-census -- --rev 5196143   →  10,253
//   mise run comment-census -- --rev 99f28fa   →  12,047
//
// The third is 103 more than the 11,944 #365 published, and the 103 is the five
// `.js` config files (`vite.config.js`, `vitest.config.js`) that that audit's
// file glob missed — `.mjs` and `.res` and `.css`, no `.js`. The two later
// figures were taken with those files in, and both land exactly. No single
// definition reaches all three published numbers, which is the drift this task
// exists to end; `.js` is in, because a config file is source.

import { execFileSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { dirname, resolve } from "node:path"

// The definition #365 established. Keeping it verbatim is what makes every
// number either audit quoted still comparable, so it is stated in the output
// rather than left in here for a reader to rediscover.
const COMMENT_MARKER = /^\s*(\/\/|\/\*|\*)/

// Grouped the way the audits reported them. A file's language is decided by
// extension alone; anything not listed here isn't counted at all, because the
// marker above only describes C-style syntax (Markdown, TOML, YAML and JSON
// have no comment shape it could recognise).
const LANGUAGES = [
  { key: "rescript", label: "ReScript", extensions: [".res", ".resi"] },
  { key: "js", label: "JS/MJS", extensions: [".js", ".mjs", ".cjs"] },
  { key: "css", label: "CSS", extensions: [".css"] },
]

// ReScript compiles in-source to `.res.mjs`, and those carry the doc comments
// through into the output — count them and every ReScript comment lands twice.
const GENERATED = /\.res\.mjs$/

// A block over this many lines has outgrown a margin note; the audits tracked
// the count of them as the number that moved most.
const LONG_BLOCK = 20

// The `comment > code` list only means something above a floor. Without one it
// flags small files with proportionate headers — `StaticRender.res` is a
// sixteen-line header over one `@module` external, every line of it earning its
// place, and it sits at 16.0×. With the floor it flags files where the ratio
// implies real volume.
const RATIO_FLOOR = 100

// Below this, a line repeated across files is punctuation or a fragment rather
// than pasted prose — `*/`, a divider, `Top to bottom:` — and reporting those
// buries the thing worth seeing, which is a convention being pasted into a
// fourth file instead of written down once.
const MIN_REPEATED_TEXT = 20

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..")

const HELP = `mise run comment-census [-- <options>]

Reports comment lines per language and per file. Not a gate — a number.

Options:
  --rev <ref>   Census a particular commit (default: HEAD)
  --json        Emit the same data as JSON
  --help        Show this

How it counts:

  A comment line is one whose first non-space characters are '//', '/*' or '*'.
  A code line is any other non-blank line. Blank lines are neither, but they
  are in the "of N" totals, which are the files' full line counts.

  Files come from 'git ls-tree', never the filesystem: packages/*/lib/ and
  packages/cli/dist/ hold built copies of the sources, and counting those
  triples every number. Generated '.res.mjs' output is excluded for the same
  reason. Only ${LANGUAGES.map(l => l.extensions.join(" ")).join(" ")} are counted.

  A comment block is a run of consecutive comment lines. A file header is the
  block starting on the file's first non-blank line.

  'Comment > code' lists files with more comment lines than code lines and at
  least ${RATIO_FLOOR} lines in total. Without that floor the list is small files with
  proportionate headers, which is not what the rule in CLAUDE.md is about.

  'Repeated' lists comment lines of ${MIN_REPEATED_TEXT}+ characters (markers stripped) that
  appear in three or more files — a convention being pasted rather than
  written down once.`

function parseArgs(argv) {
  const opts = { rev: "HEAD", json: false, help: false }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--json") opts.json = true
    else if (arg === "--help" || arg === "-h") opts.help = true
    else if (arg === "--rev") {
      opts.rev = argv[++i]
      if (!opts.rev) throw new Error("--rev needs a commit-ish")
    } else throw new Error(`unrecognised argument: ${arg}`)
  }
  return opts
}

// No `encoding`, so stdout comes back as a Buffer: `cat-file --batch` frames
// its records by byte length, which a decoded string can't be indexed by.
function git(args, input) {
  return execFileSync("git", args, {
    cwd: REPO_ROOT,
    input: input === undefined ? undefined : Buffer.from(input, "utf8"),
    maxBuffer: 256 * 1024 * 1024,
  })
}

function languageOf(path) {
  if (GENERATED.test(path)) return null
  return LANGUAGES.find(lang => lang.extensions.some(ext => path.endsWith(ext))) ?? null
}

// `git ls-tree -r -z` gives "<mode> <type> <oid>\t<path>" per NUL-separated
// record; keeping the oid means the contents come back from `cat-file --batch`
// in one round trip rather than one process per file.
function listFiles(rev) {
  const out = git(["ls-tree", "-r", "-z", rev]).toString("utf8")
  const files = []
  for (const record of out.split("\0")) {
    if (!record) continue
    const tab = record.indexOf("\t")
    const [, type, oid] = record.slice(0, tab).split(/\s+/)
    const path = record.slice(tab + 1)
    if (type !== "blob") continue
    const language = languageOf(path)
    if (language) files.push({ path, oid, language })
  }
  return files.sort((a, b) => a.path.localeCompare(b.path))
}

// `cat-file --batch` answers "<oid> <type> <size>\n<contents>\n" per requested
// oid, in order. Sizes are bytes, so the response has to be walked as a buffer.
function readBlobs(files) {
  if (!files.length) return new Map()
  const response = git(["cat-file", "--batch"], files.map(f => f.oid).join("\n") + "\n")
  const contents = new Map()
  let at = 0
  for (const file of files) {
    const newline = response.indexOf(0x0a, at)
    const size = Number(response.toString("utf8", at, newline).split(" ")[2])
    const start = newline + 1
    contents.set(file.path, response.toString("utf8", start, start + size))
    at = start + size + 1
  }
  return contents
}

function measure(path, language, text) {
  const lines = text.split("\n")
  // A trailing newline is a terminator, not an empty last line.
  if (lines.length && lines[lines.length - 1] === "") lines.pop()

  const flags = lines.map(line => COMMENT_MARKER.test(line))
  const comments = flags.filter(Boolean).length
  const blank = lines.filter(line => line.trim() === "").length

  const blocks = []
  let run = 0
  for (const isComment of flags) {
    if (isComment) run++
    else if (run) {
      blocks.push(run)
      run = 0
    }
  }
  if (run) blocks.push(run)

  const firstContent = lines.findIndex(line => line.trim() !== "")
  const header = firstContent >= 0 && flags[firstContent] ? blocks[0] : 0

  const commentText = lines
    .filter((_, i) => flags[i])
    .map(line => line.trim().replace(/^(\/\/|\/\*|\*\/|\*)\s?/, "").trim())

  return {
    path,
    language: language.key,
    lines: lines.length,
    comments,
    code: lines.length - comments - blank,
    blank,
    blocks,
    header,
    commentText,
  }
}

function median(sorted) {
  if (!sorted.length) return 0
  const mid = sorted.length >> 1
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

function percentile(sorted, p) {
  if (!sorted.length) return 0
  return sorted[Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)]
}

function census(rev) {
  const files = listFiles(rev)
  const contents = readBlobs(files)
  const measured = files.map(f => measure(f.path, f.language, contents.get(f.path)))

  const languages = LANGUAGES.map(lang => {
    const own = measured.filter(m => m.language === lang.key)
    return {
      key: lang.key,
      label: lang.label,
      files: own.length,
      lines: own.reduce((n, m) => n + m.lines, 0),
      comments: own.reduce((n, m) => n + m.comments, 0),
    }
  })

  const total = {
    files: measured.length,
    lines: languages.reduce((n, l) => n + l.lines, 0),
    comments: languages.reduce((n, l) => n + l.comments, 0),
  }

  const allBlocks = measured.flatMap(m => m.blocks).sort((a, b) => a - b)
  const longBlocks = measured.flatMap(m => m.blocks.filter(b => b > LONG_BLOCK))

  const headers = measured.filter(m => m.header > 0)

  // Sorted by ratio, but reported with the size column: the rule in CLAUDE.md
  // needs both to mean anything. After #387 the *count* of ReScript files over
  // 1.0× went up, 20 → 21, while the volume in them collapsed — a move only
  // visible when the two numbers sit next to each other.
  const commentHeavy = measured
    .filter(m => m.comments > m.code && m.lines >= RATIO_FLOOR)
    // A file with no code line at all has no ratio, not an infinite one — JSON
    // has no `Infinity`, so it would serialise as `null` anyway.
    .map(m => ({ ...m, ratio: m.code === 0 ? null : m.comments / m.code }))
    .sort((a, b) => (b.ratio ?? Infinity) - (a.ratio ?? Infinity) || b.comments - a.comments)

  const seenIn = new Map()
  for (const m of measured) {
    for (const text of new Set(m.commentText)) {
      if (text.length < MIN_REPEATED_TEXT) continue
      if (!seenIn.has(text)) seenIn.set(text, [])
      seenIn.get(text).push(m.path)
    }
  }
  const repeated = [...seenIn]
    .filter(([, paths]) => paths.length >= 3)
    .map(([text, paths]) => ({ text, files: paths.length, paths }))
    .sort((a, b) => b.files - a.files || a.text.localeCompare(b.text))

  return {
    rev,
    commit: git(["rev-parse", rev]).toString("utf8").trim(),
    definition: "first non-space characters are // or /* or *",
    languages,
    total,
    blocks: {
      count: allBlocks.length,
      median: median(allBlocks),
      p90: percentile(allBlocks, 90),
      over: LONG_BLOCK,
      overCount: longBlocks.length,
      overLines: longBlocks.reduce((n, b) => n + b, 0),
    },
    headers: {
      files: headers.length,
      lines: headers.reduce((n, m) => n + m.header, 0),
      largest: headers
        .sort((a, b) => b.header - a.header || a.path.localeCompare(b.path))
        .slice(0, 8)
        .map(m => ({ path: m.path, header: m.header, lines: m.lines })),
    },
    commentHeavy: commentHeavy.map(m => ({
      path: m.path,
      comments: m.comments,
      code: m.code,
      lines: m.lines,
      ratio: m.ratio === null ? null : Number(m.ratio.toFixed(2)),
    })),
    repeated,
    files: measured.map(m => ({
      path: m.path,
      language: m.language,
      lines: m.lines,
      comments: m.comments,
      code: m.code,
      header: m.header,
    })),
  }
}

const n = value => value.toLocaleString("en-US")
const basename = path => path.slice(path.lastIndexOf("/") + 1)

// Two lists printed side by side, each already formatted; the shorter one is
// padded out with blanks so the columns stay square whichever runs longer.
function columns(left, right, gap) {
  const width = Math.max(0, ...left.rows.map(r => r.length), left.title.length)
  const rows = []
  rows.push(left.title.padEnd(width) + gap + right.title)
  for (let i = 0; i < Math.max(left.rows.length, right.rows.length); i++) {
    rows.push(((left.rows[i] ?? "").padEnd(width) + gap + (right.rows[i] ?? "")).trimEnd())
  }
  return rows
}

function render(data) {
  const { languages, total, blocks, headers, commentHeavy, repeated } = data
  const out = []

  const commentWidth = Math.max(...languages.map(l => n(l.comments).length), n(total.comments).length)
  const lineWidth = Math.max(...languages.map(l => n(l.lines).length), n(total.lines).length)

  out.push("")
  for (const lang of languages) {
    const pct = lang.lines ? Math.round((lang.comments / lang.lines) * 100) : 0
    out.push(
      `  ${lang.label.padEnd(10)}${n(lang.comments).padStart(commentWidth)} of ` +
        `${n(lang.lines).padStart(lineWidth)}   ${String(pct).padStart(2)}%   ` +
        `${String(lang.files).padStart(3)} files`,
    )
  }
  const totalPct = total.lines ? ((total.comments / total.lines) * 100).toFixed(1) : "0.0"
  out.push("  " + "─".repeat(45))
  out.push(
    `  ${"TOTAL".padEnd(10)}${n(total.comments).padStart(commentWidth)} of ` +
      `${n(total.lines).padStart(lineWidth)}   ${totalPct}%`,
  )

  const headerRows = headers.largest.map(
    h => `${basename(h.path).padEnd(22)}${String(h.header).padStart(3)}`,
  )
  const heavyRows = commentHeavy.length
    ? commentHeavy.map(
        f =>
          `${basename(f.path).padEnd(22)}${(f.ratio === null ? "∞" : `${f.ratio.toFixed(1)}×`).padStart(6)}` +
          `${String(f.lines).padStart(6)} lines`,
      )
    : ["(none)"]

  out.push("")
  out.push(
    ...columns(
      { title: "Largest headers", rows: headerRows },
      { title: `Comment > code (${RATIO_FLOOR}+ lines)`, rows: heavyRows },
      "    ",
    ).map(row => "  " + row),
  )

  out.push("")
  out.push(
    `  Blocks     ${n(blocks.count)} runs of comment lines — median ${blocks.median}, ` +
      `p90 ${blocks.p90}, ${blocks.overCount} over ${blocks.over} lines (${n(blocks.overLines)} lines)`,
  )
  out.push(
    `  Headers    ${n(headers.files)} files, ${n(headers.lines)} lines, ` +
      `avg ${Math.round(headers.lines / Math.max(1, headers.files))}`,
  )
  out.push(
    `  Repeated   ${repeated.length} comment lines appear in 3+ files` +
      (repeated.length ? ":" : ""),
  )
  for (const line of repeated) {
    const text = line.text.length > 62 ? line.text.slice(0, 61) + "…" : line.text
    out.push(`             ${String(line.files).padStart(2)}×  ${text}`)
  }

  out.push("")
  out.push(`  A comment line is one whose first non-space characters are // or /* or *.`)
  out.push(`  Tracked files at ${data.commit.slice(0, 7)}; generated .res.mjs excluded.`)
  out.push("")
  return out.join("\n")
}

const opts = parseArgs(process.argv.slice(2))
if (opts.help) {
  console.log(HELP)
} else {
  const data = census(opts.rev)
  console.log(opts.json ? JSON.stringify(data, null, 2) : render(data))
}
