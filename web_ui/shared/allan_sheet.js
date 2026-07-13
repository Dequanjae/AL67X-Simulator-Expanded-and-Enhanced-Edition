/**
 * allan_sheet.js — shared helper for cropping a single expression frame out
 * of the player1.png reaction sheet (8x2 grid, 879x1185/frame — see
 * data/allans/allans.json sheet_layout). Used anywhere a popup needs a
 * reaction face (chest opens, card picks, failed merge moves) instead of
 * a generic icon, per the asset-reuse rule.
 *
 * NOTE: only "idle" (0), "eat" (5), "succ" (7, used as our best-fit
 * "shocked/excited" pose), "cry" (8) and "turn" (9) are actually populated
 * in the registered frame_map today — this helper only exposes those.
 */
const OGAllanSheet = (() => {
  const COLS = 8;
  const ROWS = 2;
  const FRAME_W = 879;
  const FRAME_H = 1185;
  // Path is relative to the depth-1 shell document (web_ui/<context>/index.html)
  // that every popup module is ultimately mounted inside of.
  const SHEET_SRC = "../../assets/sprites/allan/player1.png";

  const FRAMES = { idle: 0, eat: 5, excited: 7, cry: 8, turn: 9 };

  /** Applies a cropped frame as this element's background at `size` px tall.
   *  `sheetSrc` optionally overrides the default player1.png reaction sheet
   *  (e.g. merge.js passing a specific tier's own sheet for its thumbnail). */
  function applyFrame(el, frameKey, size = 96, sheetSrc = SHEET_SRC) {
    const idx = FRAMES[frameKey] ?? 0;
    const col = idx % COLS;
    const row = Math.floor(idx / COLS);
    const scale = size / FRAME_H;
    const w = FRAME_W * scale;
    const h = FRAME_H * scale;
    el.style.width = `${w}px`;
    el.style.height = `${h}px`;
    el.style.backgroundImage = `url(${OGAssets.resolve(sheetSrc)})`;
    el.style.backgroundRepeat = "no-repeat";
    el.style.backgroundSize = `${COLS * w}px ${ROWS * h}px`;
    el.style.backgroundPosition = `-${col * w}px -${row * h}px`;
  }

  /** Builds the relative sheet path for a given allan/tier sheet filename,
   *  e.g. sheetPathFor("player3") -> "../../assets/sprites/allan/player3.png". */
  function sheetPathFor(allanId) {
    return `../../assets/sprites/allan/${allanId}.png`;
  }

  return { applyFrame, sheetPathFor, FRAMES };
})();

window.OGAllanSheet = OGAllanSheet;
