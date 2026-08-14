// Writing text to the system clipboard, wrapped so callers get a plain
// "did it land?" answer instead of a promise that might reject or an API that
// might not be there at all.
//
// `navigator.clipboard` is **not** universally present: the spec gates it on a
// secure context, so it's `undefined` over plain http (a phone hitting a dev box
// by LAN IP is the case that bites in this project — the same origins where
// Wiggle Waggle's motion sensor is blocked, see `Motion`). It's read as nullable
// for that reason, exactly like `Refresh` reads `navigator.serviceWorker`.
//
// Even when present, `writeText` rejects when the document isn't focused or the
// user denied clipboard permission. Both failure shapes — missing API, rejected
// write — collapse into `copy` resolving `false`, so a caller has one thing to
// check and the UI can say "couldn't copy" rather than swallowing it silently or
// throwing an unhandled rejection into the console.

type clipboard

@val @scope("navigator") external clipboard: Nullable.t<clipboard> = "clipboard"

@send external writeText: (clipboard, string) => promise<unit> = "writeText"

// Put `text` on the clipboard, resolving whether it actually got there. Never
// rejects: an unsupported browser (or insecure origin) resolves `false` without
// touching the API, and a rejected write is caught and reported the same way.
let copy = async (text: string): bool =>
  switch clipboard->Nullable.toOption {
  | None => false
  | Some(c) =>
    try {
      await c->writeText(text)
      true
    } catch {
    // Any rejection — permission denied, document not focused — is a failed copy.
    | _ => false
    }
  }
