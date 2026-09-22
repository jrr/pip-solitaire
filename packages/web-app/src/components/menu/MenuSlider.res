// A number on a slider, in the menu: the label and the value it is at on one line, the
// track under them. The menu twin of the demo scenes' `knob`, and it reads the value out
// for the same reason that one does — a slider alone says "somewhere in the middle", and
// what you want to leave with is a number you could put in the source.
//
// **Not a `<MenuRow>`.** Every row on this panel is a `<button>` with an action, and a
// range input inside a button is a control the button would swallow the drags of. So this
// is its own box, wearing the same `--control-*` clothes.
//
// The readout is the caller's string rather than a format this knows: what a number means
// — a half-life, a fill every so many milliseconds — is the caller's subject, and a
// component that formatted it would be the second place that knows.
%%raw(`import "./MenuSlider.css"`)

type props = {
  // What the control is called, and the `data-knob` a test reaches it by — the same
  // attribute the demo scenes' sliders carry, because it is the same idea.
  label: string,
  min: float,
  max: float,
  step: float,
  value: float,
  // The value in words, sitting where a row's description would.
  readout: string,
  onInput: float => unit,
}

// A slider as *data*, for a screen whose controls a caller knows and a component draws —
// the trick `MenuRow.entry` plays for rows, so a screen can take a list of these and grow
// a control without growing two props. An alias: both names are this one type.
type spec = props

let make = ({label, min, max, step, value, readout, onInput}) =>
  <div className="menu-slider">
    <div className="menu-slider__head">
      <span className="menu-slider__label"> {Html.string(label)} </span>
      <span className="menu-slider__readout"> {Html.string(readout)} </span>
    </div>
    <input
      className="menu-slider__track"
      type_="range"
      min={Float.toString(min)}
      max={Float.toString(max)}
      step={Float.toString(step)}
      // Controlled, like the seed dialog's field: what is on screen is the value the
      // model holds, so a slider dragged on one screen reads right when the menu is
      // reopened on another.
      value={Float.toString(value)}
      dataKnob=label
      ariaLabel=label
      // A range input's value is always a number its own `min`/`max`/`step` allow, so
      // the one thing to decide here is what an engine that hands back nonsense gets:
      // nothing, rather than a `0.` that would jump the control to one end.
      onInput={event => Html.inputValue(event)->Float.fromString->Option.forEach(onInput)}
    />
  </div>
