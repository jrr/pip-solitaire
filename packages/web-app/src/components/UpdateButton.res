// The "Update available — reload" button. Hidden until the service worker
// reports a waiting update; clicking it activates the new worker and reloads to
// the fresh version. See VersionBadge for why the `props` record is spelled out
// rather than derived by the `@jsx.component` sugar. Layout for `#update-button`
// lives in the stylesheet in index.html.
type props = {visible: bool, onReload: unit => unit}

let make = ({visible, onReload}) =>
  <button id="update-button" hidden={!visible} onClick={_ => onReload()}>
    {Html.string("Update available — reload")}
  </button>
