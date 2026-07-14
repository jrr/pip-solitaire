// A placeholder scene — a "Coming soon" stub. It exists only to prove the
// switcher handles more than one entry; swap it for a real demo (drag-and-drop
// #21, animation #22, a card gallery, …) when one lands.

let make = (): Scene.t => {
  id: "coming-soon",
  label: "Coming soon",
  mount: container => {
    let stub = WebDom.createElement("p")
    stub->WebDom.setAttribute("class", "scene-placeholder")
    stub->WebDom.setTextContent("Coming soon…")
    container->WebDom.appendChild(stub)->ignore
    () => ()
  },
}
