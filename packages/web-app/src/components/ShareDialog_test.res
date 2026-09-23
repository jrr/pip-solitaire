// The Debug screen's "Share game state" modal. The link arrives already built, so the
// cases are what the panel shows for it and the ways out — a copy, a close — that
// reach the caller.
open Vitest
open TestDom

let url = "https://example.test/pip/#g=abc"

let render = (
  ~url=url,
  ~scan=Some({ShareLink.url, dropped: 0}),
  ~status=None,
  ~onCopy=() => (),
  ~onClose=() => (),
) => Html.create(ShareDialog.make({url, scan, status, onCopy, onClose}))

let buttons = (dialog): array<element> => dialog->findAll(".share-dialog__button")
let hint = dialog => dialog->textIn(".share-dialog__hint")

describe("ShareDialog", () => {
  test("shows the link as a QR code and as text", () => {
    let dialog = render()
    expect(dialog->has(".share-dialog__qr .qr-code"))->toBe(true)
    expect(dialog->textIn(".share-dialog__url"))->toBe(url)
  })

  test("copies when Copy is pressed", () => {
    let copies = ref(0)
    render(~onCopy=() => copies := copies.contents + 1)->buttons->Array.getUnsafe(1)->click
    expect(copies.contents)->toBe(1)
  })

  test("reports where the link went in the hint's place, so the panel keeps its height", () => {
    expect(render()->hint)->toBe(ShareDialog.hint)
    let dialog = render(~status=Some("Link copied to clipboard."))
    expect(dialog->hint)->toBe("Link copied to clipboard.")
    expect(dialog->findAll(".share-dialog__hint")->Array.length)->toBe(1)
  })

  test("says so and still offers the copy when the link won't fit in a QR code", () => {
    let dialog = render(~url=String.repeat("x", 5000), ~scan=None)
    expect(dialog->has(".qr-code"))->toBe(false)
    expect(dialog->hint)->toBe(ShareDialog.tooLong)
    expect(dialog->buttons->Array.map(text))->toEqual(["Close", "Copy link"])
  })

  test("says what a trimmed code left out, and still shows the whole link as text", () => {
    let full = url ++ String.repeat("x", 5000)
    let dialog = render(~url=full, ~scan=Some({url, dropped: 12}))
    expect(dialog->has(".share-dialog__qr .qr-code"))->toBe(true)
    expect(dialog->hint)->toBe(ShareDialog.trimmedHint(~dropped=12))
    expect(dialog->textIn(".share-dialog__url"))->toBe(full)
  })

  test("closes from its button and from the dim behind it", () => {
    let closes = ref(0)
    let dialog = render(~onClose=() => closes := closes.contents + 1)
    dialog->buttons->Array.getUnsafe(0)->click
    dialog->find(".share-dialog__backdrop")->Option.getOrThrow->click
    expect(closes.contents)->toBe(2)
  })

  test("announces itself as a modal dialog, since it covers everything", () => {
    let dialog = render()
    expect(dialog->attrOr("role"))->toBe("dialog")
    expect(dialog->attrOr("aria-modal"))->toBe("true")
    expect(dialog->attrOr("aria-label"))->toBe("Share game state")
  })
})
