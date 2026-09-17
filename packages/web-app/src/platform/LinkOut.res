// The one thing about a link out of the app that isn't the link's own business: whether
// it asks for a tab of its own. Both of the app's `<a>`s — the game info screen's
// Wikipedia article, the About screen's repository — ask this module rather than writing
// `target` themselves, because the answer depends on where the app is running and not on
// which link it is.
//
// **In a browser, a tab of its own.** Following a link in place would tear a board down
// mid-play, and the game is what the reader came back to.
//
// **In an iOS Home Screen web app, no target at all** — which is the opposite of what it
// looks like it should be, so don't "fix" it back. Apple routes a navigation *out of the
// manifest's scope* to the reader's browser, and a `target="_blank"` or `window.open()`
// load into a browser view inside the web app instead: "links loaded through window.open
// will always open in the web app regardless of scope" (WWDC23, "What's new in web
// apps"; the app's scope is `./`, set in vite.config.js, so en.wikipedia.org is outside
// it). Asking for a tab is therefore what pins the article inside the app, and asking for
// nothing is what gets it out. The board survives either way: an out-of-scope link does
// not navigate the web app.
//
// What that buys is the system's own browser view over the app, which the reader closes
// to find the board where they left it, rather than a page the app has swallowed. **It is
// not the browser as a separate app**: no web API reaches that, so a reader who wants
// Safari proper goes through the view's own share sheet, and there is nothing here that
// can save them the step.
//
// `navigator.standalone` is the iOS-only flag for that mode, and the guard is what keeps
// this readable in bare Node — `StaticRender` renders components with no `navigator` at
// all (scripts/generate/icons.mjs, and the screenshots report).
let isHomeScreenApp: unit => bool = %raw(`() =>
  typeof navigator !== "undefined" && navigator.standalone === true
`)

// Read per render rather than once at load: a module-level constant would be decided
// before a test could say which platform it is standing in.
let target = (): option<string> => isHomeScreenApp() ? None : Some("_blank")
