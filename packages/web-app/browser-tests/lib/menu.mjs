// Shared readings of the main menu for the browser suite.
//
// Not a spec file — Playwright only collects `*.spec.mjs` from browser-tests/,
// so helpers live here beside them.

/**
 * The deal number the menu names, which four suites want and none of them owns:
 * the seed of the board on the table. It is the "this game" heading that says it,
 * so that both controls under the heading — Restart and Share Seed — are visibly
 * about the same board. There is no element at all on a board with no seed, which
 * is why this is a locator to assert against rather than a string to read.
 *
 * Its text is the number behind a `#` — "#24680", the heading's own spelling (see
 * MenuSection.res) — so assert against that rather than the bare digits. A negative
 * assertion especially: `not.toHaveText("13579")` passes against "#13579" for the
 * wrong reason, and passes just as well against a seed that never changed.
 */
export const menuSeed = (page) => page.locator('[aria-label="this game"] .menu-section__value')
