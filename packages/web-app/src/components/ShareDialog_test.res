// The Debug screen's "Share game state" modal. The link arrives already built, so the
// cases are what the panel shows for it and the ways out — a copy, a close — that
// reach the caller.
open Vitest
open TestDom

let url = "https://example.test/pip/#g=abc"

let render = (
  ~scan=Some({ShareLink.url, kept: 40, total: 40}),
  ~status=None,
  ~onCopy=() => (),
  ~onClose=() => (),
) => Html.create(ShareDialog.make({scan, status, onCopy, onClose}))

let buttons = (dialog): array<element> => dialog->findAll(".share-dialog__button")
let hint = dialog => dialog->textIn(".share-dialog__hint")

describe("ShareDialog", () => {
  test("shows the link as a QR code, with nothing said about history when it's all there", () => {
    let dialog = render()
    expect(dialog->has(".share-dialog__qr .qr-code"))->toBe(true)
    expect(dialog->has(".share-dialog__truncated"))->toBe(false)
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
    let dialog = render(~scan=None)
    expect(dialog->has(".qr-code"))->toBe(false)
    expect(dialog->hint)->toBe(ShareDialog.tooLong)
    expect(dialog->buttons->Array.map(text))->toEqual(["Close", "Copy link"])
  })

  test("says how much history a trimmed code kept, beside the hint rather than in it", () => {
    let dialog = render(~scan=Some({url, kept: 93, total: 300}))
    expect(dialog->has(".share-dialog__qr .qr-code"))->toBe(true)
    expect(dialog->hint)->toBe(ShareDialog.hint)
    expect(dialog->textIn(".share-dialog__truncated"))->toBe(
      "QR code discarded history. (94/301 states kept)",
    )
  })

  test("keeps the truncation note up while a Copy's status stands in for the hint", () => {
    let dialog = render(
      ~scan=Some({url, kept: 93, total: 300}),
      ~status=Some("Link copied to clipboard."),
    )
    expect(dialog->hint)->toBe("Link copied to clipboard.")
    expect(dialog->has(".share-dialog__truncated"))->toBe(true)
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
