// The Spinner scene: the <game-board> spike (#29) rehomed into a switchable
// scene. Behaviour is unchanged from the original inline `#board-demo` section —
// same inward `Flip` / outward `card-poked` wiring — it just mounts into the
// shared scene container and its nodes are cleared when another scene is
// selected. A fresh <game-board> is created each time the scene mounts, so
// re-selecting it starts the spin over from a clean slate.

// The <game-board> element's inward conduit (see game-board.js / InwardEvents).
@send external send: (WebDom.element, InwardEvents.command) => unit = "send"

// The <game-board> custom element is plain JS; register it before creating one.
@module("./game-board.js") external registerBoard: unit => unit = "register"

let make = (): Scene.t => {
  id: "spinner",
  label: "Spinner",
  mount: container => {
    registerBoard()

    let board = WebDom.createElement("game-board")
    container->WebDom.appendChild(board)->ignore

    // inward: send a typed command in; the board owns the spin state and flips it.
    let flipButton = WebDom.createElement("button")
    flipButton->WebDom.setAttribute("id", "flip-button")
    flipButton->WebDom.setTextContent("Reverse spin")
    container->WebDom.appendChild(flipButton)->ignore
    flipButton->WebDom.addEventListener("click", () => board->send(InwardEvents.Flip))

    // outward: read the angle the board reports when the card is poked.
    let readout = WebDom.createElement("p")
    readout->WebDom.setAttribute("id", "board-readout")
    readout->WebDom.setTextContent("Tap the card…")
    container->WebDom.appendChild(readout)->ignore
    OutwardEvents.CardPoked.on(board, ({angle}) => {
      let deg = Math.round(angle)->Float.toString
      readout->WebDom.setTextContent(`card pointed at ${deg}°`)
    })

    // No extra teardown: the switcher clears the container, and the detached
    // <game-board> (and its WAAPI spin) is dropped with it.
    () => ()
  },
}
