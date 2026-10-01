// Times and sizes the way the benchmark record writes them (docs/solver.md).

export const time = (ms) => (ms < 1 ? "<1 ms" : ms < 1000 ? `${Math.round(ms)} ms` : `${(ms / 1000).toFixed(1)} s`)

export const mb = (bytes) => (bytes < 1e6 ? "<1 MB" : `${(bytes / 1e6).toFixed(0)} MB`)

// `1-200 7 9-12` → [1, …, 200, 7, 9, …, 12]; anything else is the caller's to parse.
export function seedsOf(arg) {
  if (/^\d+-\d+$/.test(arg)) {
    const [from, to] = arg.split("-").map(Number)
    return Array.from({ length: Math.max(to - from + 1, 0) }, (_, i) => from + i)
  }
  if (/^\d+$/.test(arg)) return [Number(arg)]
  return null
}

// A list of seeds as the record writes a range: `1–200`, or `1–100, 150`.
export function rangeOf(seeds) {
  const sorted = [...new Set(seeds)].sort((a, b) => a - b)
  const runs = []
  for (const s of sorted) {
    const last = runs.at(-1)
    if (last && s === last[1] + 1) last[1] = s
    else runs.push([s, s])
  }
  return runs.map(([a, b]) => (a === b ? `${a}` : `${a}–${b}`)).join(", ")
}
