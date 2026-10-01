// A solver build in its own process (think.mjs), asked one deal at a time.

import { fork } from "node:child_process"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const core = resolve(dirname(fileURLToPath(import.meta.url)), "../..")

export const headSrc = join(core, "src")

export function startThinker(src) {
  const child = fork(join(core, "scripts/lib/think.mjs"), [src], { execArgv: ["--expose-gc"] })
  let waiting = null
  const ready = new Promise((resolve) => (waiting = resolve))
  child.on("message", (message) => {
    const answer = waiting
    waiting = null
    answer(message)
  })
  child.on("exit", (code) => {
    if (waiting) waiting({ error: `the thinker for ${src} exited (${code})` })
  })
  return {
    async ask(task) {
      await ready
      if (!child.connected) throw new Error(`the thinker for ${src} has exited`)
      const answer = new Promise((resolve) => (waiting = resolve))
      child.send(task)
      const result = await answer
      if (result.error) throw new Error(`${src}, ${task.game} #${task.seed}: ${result.error}`)
      return result
    },
    close: () => child.kill(),
  }
}
