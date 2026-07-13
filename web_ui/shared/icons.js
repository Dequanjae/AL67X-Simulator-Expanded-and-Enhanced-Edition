/**
 * icons.js — the single cohesive icon set for Overvolt Garage. Duotone
 * outline style: 2px currentColor stroke, flat accent fill on a secondary
 * tone, 24x24 viewBox unless noted. Every screen pulls icons from here
 * instead of hand-rolling one-off SVGs, so the stroke width/style never
 * drifts between screens.
 *
 * Usage: OGIcons.bolt(), OGIcons.gear(), etc. return an SVG markup string.
 */
const OGIcons = (() => {
  const wrap = (body, viewBox = "0 0 24 24") =>
    `<svg viewBox="${viewBox}" fill="none" xmlns="http://www.w3.org/2000/svg">${body}</svg>`;

  return {
    // Nav rail: Home
    home: () =>
      wrap(`
      <path d="M3 11L12 4l9 7" stroke="#1c1c1c" stroke-width="2" stroke-linejoin="round"/>
      <path d="M5 10v9a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1v-9" stroke="#1c1c1c" stroke-width="2" fill="#ffd400" stroke-linejoin="round"/>
    `),
    // Nav rail: Cards (deck)
    cards: () =>
      wrap(`
      <rect x="4" y="6" width="12" height="16" rx="2" transform="rotate(-8 10 14)" fill="#16d1ff" stroke="#1c1c1c" stroke-width="2"/>
      <rect x="8" y="3" width="12" height="16" rx="2" fill="#fffaf0" stroke="#1c1c1c" stroke-width="2"/>
      <path d="M11 8h6M11 11h6M11 14h3" stroke="#1c1c1c" stroke-width="1.5" stroke-linecap="round"/>
    `, "0 0 24 24"),
    // Nav rail: Merge (fusion bolt-loop)
    merge: () =>
      wrap(`
      <rect x="3" y="3" width="8" height="8" rx="2" fill="#ff9248" stroke="#1c1c1c" stroke-width="2"/>
      <rect x="13" y="3" width="8" height="8" rx="2" fill="#ffd400" stroke="#1c1c1c" stroke-width="2"/>
      <rect x="8" y="13" width="8" height="8" rx="2" fill="#16d1ff" stroke="#1c1c1c" stroke-width="2"/>
      <path d="M11 11l2 2" stroke="#1c1c1c" stroke-width="2" stroke-linecap="round"/>
    `),
    // Nav rail: Shop
    shop: () =>
      wrap(`
      <path d="M4 8l1.5-4h13L20 8" stroke="#1c1c1c" stroke-width="2" stroke-linejoin="round" fill="#fffaf0"/>
      <path d="M4 8h16v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8z" fill="#ff6a13" stroke="#1c1c1c" stroke-width="2"/>
      <path d="M9 12a3 3 0 0 0 6 0" stroke="#1c1c1c" stroke-width="2" stroke-linecap="round"/>
    `),
    // Chrome: News / megaphone
    news: () =>
      wrap(`
      <path d="M3 10v4a2 2 0 0 0 2 2h1l2 5 1-5h1l9 3V7l-9 3H6a2 2 0 0 0-2 2z" fill="#fffaf0" stroke="#1c1c1c" stroke-width="2" stroke-linejoin="round"/>
      <circle cx="19" cy="9.5" r="1.4" fill="#ff3d8f"/>
    `),
    // Chrome: Mail
    mail: () =>
      wrap(`
      <rect x="3" y="5" width="18" height="14" rx="2" fill="#fffaf0" stroke="#1c1c1c" stroke-width="2"/>
      <path d="M4 6.5l8 6 8-6" stroke="#1c1c1c" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    `),
    // Chrome: Settings gear
    gear: () =>
      wrap(`
      <circle cx="12" cy="12" r="3.2" fill="#16d1ff" stroke="#1c1c1c" stroke-width="2"/>
      <path d="M12 3.5v2.4M12 18.1v2.4M20.5 12h-2.4M5.9 12H3.5M17.7 6.3l-1.7 1.7M8 16l-1.7 1.7M17.7 17.7L16 16M8 8L6.3 6.3"
        stroke="#1c1c1c" stroke-width="2" stroke-linecap="round"/>
    `),
    // Resource: Amps bolt
    bolt: () =>
      wrap(`
      <path d="M13 2L4 14h6l-1 8 9-12h-6z" fill="#ff6a13" stroke="#1c1c1c" stroke-width="2" stroke-linejoin="round"/>
    `),
    // Resource: AL67X token coin
    token: () =>
      wrap(`
      <circle cx="12" cy="12" r="9" fill="#16d1ff" stroke="#1c1c1c" stroke-width="2"/>
      <path d="M12 7l3.5 3.5L12 14l-3.5-3.5z" fill="#fffaf0" stroke="#1c1c1c" stroke-width="1.4"/>
    `),
    // Wrench prop (character hip + shop tags)
    wrench: () =>
      wrap(`
      <path d="M14.7 6.3a4 4 0 1 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.1 2.1-2-.6-.6-2z"
        fill="#333333" stroke="#1c1c1c" stroke-width="2" stroke-linejoin="round"/>
    `),
    // Close / X
    close: () =>
      wrap(`
      <path d="M6 6l12 12M18 6L6 18" stroke="#1c1c1c" stroke-width="2.5" stroke-linecap="round"/>
    `),
    // Back chevron
    back: () =>
      wrap(`
      <path d="M15 5l-7 7 7 7" stroke="#1c1c1c" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    `),
    // Chest / loot box
    chest: () =>
      wrap(`
      <rect x="3" y="10" width="18" height="10" rx="2" fill="#ff9248" stroke="#1c1c1c" stroke-width="2"/>
      <path d="M3 10a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4" fill="#ff6a13" stroke="#1c1c1c" stroke-width="2"/>
      <rect x="10" y="10" width="4" height="5" fill="#ffd400" stroke="#1c1c1c" stroke-width="1.5"/>
    `),
    // Instagram-style camera glyph (fallback follow card)
    instagram: () =>
      wrap(`
      <rect x="3" y="3" width="18" height="18" rx="5" fill="#fffaf0" stroke="#1c1c1c" stroke-width="2"/>
      <circle cx="12" cy="12" r="4" fill="none" stroke="#1c1c1c" stroke-width="2"/>
      <circle cx="17" cy="7" r="1.3" fill="#1c1c1c"/>
    `),
    // Speaker / audio settings
    speaker: () =>
      wrap(`
      <path d="M4 9v6h4l5 4V5L8 9H4z" fill="#ffd400" stroke="#1c1c1c" stroke-width="2" stroke-linejoin="round"/>
      <path d="M17 9a4 4 0 0 1 0 6" stroke="#1c1c1c" stroke-width="2" stroke-linecap="round"/>
    `),
    // Star (rarity / rating)
    star: () =>
      wrap(`
      <path d="M12 3l2.6 5.9 6.4.6-4.8 4.3 1.4 6.3L12 16.9 6.4 20.1l1.4-6.3-4.8-4.3 6.4-.6z"
        fill="#ffd400" stroke="#1c1c1c" stroke-width="1.6" stroke-linejoin="round"/>
    `),
    // Sparkle (VFX accent, small)
    sparkle: () =>
      wrap(`
      <path d="M12 2l1.3 6.7L20 10l-6.7 1.3L12 18l-1.3-6.7L4 10l6.7-1.3z" fill="#16d1ff" stroke="#1c1c1c" stroke-width="1.2"/>
    `),
    // Heart (HP, filled or empty per `full`)
    heart: (full = true) =>
      wrap(`
      <path d="M12 20.5S3 14.8 3 8.6A4.6 4.6 0 0 1 12 6a4.6 4.6 0 0 1 9 2.6c0 6.2-9 11.9-9 11.9z"
        fill="${full ? "#ff3d3d" : "none"}" stroke="#1c1c1c" stroke-width="2" stroke-linejoin="round"/>
    `),
    // Shield (Aura Shield charge)
    shield: () =>
      wrap(`
      <path d="M12 3l7 3v6c0 5-3.5 8-7 9-3.5-1-7-4-7-9V6z" fill="#16d1ff" stroke="#1c1c1c" stroke-width="2" stroke-linejoin="round"/>
    `),
    // Pause
    pause: () =>
      wrap(`
      <rect x="6" y="5" width="4" height="14" rx="1.5" fill="#fffaf0" stroke="#1c1c1c" stroke-width="2"/>
      <rect x="14" y="5" width="4" height="14" rx="1.5" fill="#fffaf0" stroke="#1c1c1c" stroke-width="2"/>
    `),
  };
})();

window.OGIcons = OGIcons;
