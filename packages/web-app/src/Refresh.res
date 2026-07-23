// The adaptive "get the latest build" control (#112). Installed to the home
// screen, the app has no browser refresh, so a stale version has no built-in
// way out. This module powers a single Settings-screen button whose label and
// behaviour both adapt to whether a service worker is registered — detected
// with `navigator.serviceWorker.getRegistration()`:
//
//   - **No service worker** (e.g. a preview build's self-destroying worker has
//     unregistered itself, so staleness is just the HTTP cache) — the button
//     reads "Refresh" and force-reloads, busting the cache. `location.reload(true)`
//     is ignored by modern browsers, so we re-fetch the document with
//     `cache: "reload"` to repopulate the HTTP cache, then reload from it.
//   - **Service worker present** (a prod install) — the button reads "Check for
//     updates" and calls `registration.update()` *without* applying anything. A
//     found update surfaces through the existing onNeedRefresh → "Update now"
//     flow (see Main); otherwise we report "up to date".
//
// It degrades gracefully when `serviceWorker` is unsupported: `detect` reports
// `Unsupported` and the button isn't shown.

// --- Browser bindings -------------------------------------------------------
// `navigator.serviceWorker` is absent on unsupported browsers, so it's read as
// nullable. `registration.installing`/`.waiting` are the live worker slots we
// poll after an update check to tell "a new version is coming" from "up to date".
type container
type registration
type worker

@val @scope("navigator")
external serviceWorker: Nullable.t<container> = "serviceWorker"

@send
external getRegistration: container => promise<Nullable.t<registration>> = "getRegistration"

// `update()` resolves once the check completes; we ignore its resolved value and
// read the *live* registration's slots instead, which is portable across the
// spec's `Promise<void>`/`Promise<registration>` history.
@send external update: registration => promise<unit> = "update"
@get external installing: registration => Nullable.t<worker> = "installing"
@get external waiting: registration => Nullable.t<worker> = "waiting"

type fetchInit = {cache: string}
type response
@val external fetch: (string, fetchInit) => promise<response> = "fetch"

@val @scope(("window", "location")) external href: string = "href"
@val @scope(("window", "location")) external reload: unit => unit = "reload"

// --- Adaptive control -------------------------------------------------------

// Which shape the button takes, decided by `detect`. `Unsupported` and the
// pre-detection state are both "don't show a button"; `detect` never yields
// `Unsupported` on a supported browser.
type mode =
  | Unsupported
  | NoWorker
  | HasWorker

// Report asynchronously whether a service worker is registered, so the button's
// label can adapt. A rejected `getRegistration()` is treated as no worker — a
// cache-only refresh is the safe fallback.
let detect = (onResult: mode => unit): unit =>
  switch serviceWorker->Nullable.toOption {
  | None => onResult(Unsupported)
  | Some(container) =>
    container
    ->getRegistration
    ->Promise.thenResolve(reg =>
      onResult(reg->Nullable.toOption->Option.isSome ? HasWorker : NoWorker)
    )
    ->Promise.catch(_ => {
      onResult(NoWorker)
      Promise.resolve()
    })
    ->ignore
  }

// The "Refresh" action for a cache-only (no-worker) install: revalidate the
// document against the server to refresh the HTTP cache, then reload. Reload
// anyway if the fetch fails — offline, we've nothing fresher to show but the
// reload is still what the user asked for.
let forceReload = (): unit =>
  fetch(href, {cache: "reload"})
  ->Promise.thenResolve(_ => reload())
  ->Promise.catch(_ => {
    reload()
    Promise.resolve()
  })
  ->ignore

// The "Check for updates" action for a real install: ask the worker to check,
// without applying. Resolves the callback with whether an update is now pending
// (a worker installing or waiting) — true means the onNeedRefresh → "Update now"
// flow will surface it, false means we're up to date. Any failure reports false.
let checkForUpdates = (onDone: bool => unit): unit =>
  switch serviceWorker->Nullable.toOption {
  | None => onDone(false)
  | Some(container) =>
    container
    ->getRegistration
    ->Promise.then(reg =>
      switch reg->Nullable.toOption {
      | None =>
        onDone(false)
        Promise.resolve()
      | Some(r) =>
        r
        ->update
        ->Promise.thenResolve(_ => {
          let pending =
            r->installing->Nullable.toOption->Option.isSome ||
              r->waiting->Nullable.toOption->Option.isSome
          onDone(pending)
        })
      }
    )
    ->Promise.catch(_ => {
      onDone(false)
      Promise.resolve()
    })
    ->ignore
  }
