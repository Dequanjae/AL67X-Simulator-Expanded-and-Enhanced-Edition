/**
 * hub_shell.js — SPA-shell view switching for the Hub WebView. All hub
 * "screens" (Home/Shop/Settings/Merge/Deck) live in ONE loaded page and are
 * toggled via CSS class, never via WebView.load_url() — this avoids a full
 * webview reload (and JS state loss) every time the player taps a nav tab,
 * matching how the existing hub already switches tabs instantly.
 *
 * Presentation: each nav tab is framed as a ROOM at Allan's base — leaving
 * a room does a quick push-away+dim, entering the next does a push-in from
 * a doorway (scale up from small + fade), rather than an instant swap.
 */
(() => {
  const VIEWS = ["home", "shop", "settings", "merge", "deck"];
  const TRANSITION_MS = 260;
  let transitioning = false;

  function showView(tab) {
    if (transitioning) return;
    const outgoing = VIEWS.find((v) => {
      const el = document.getElementById(`view-${v}`);
      return el && el.classList.contains("is-active");
    });
    if (outgoing === tab) return;

    transitioning = true;
    const outEl = outgoing ? document.getElementById(`view-${outgoing}`) : null;
    const inEl = document.getElementById(`view-${tab}`);

    if (outEl) outEl.classList.add("og-room-leaving");

    setTimeout(() => {
      VIEWS.forEach((v) => {
        const el = document.getElementById(`view-${v}`);
        if (el) el.classList.toggle("is-active", v === tab);
      });
      if (outEl) outEl.classList.remove("og-room-leaving");
      if (inEl) {
        inEl.classList.add("og-room-entering");
        setTimeout(() => inEl.classList.remove("og-room-entering"), TRANSITION_MS);
      }
      document.querySelectorAll(".og-nav-badge").forEach((btn) => {
        btn.classList.toggle("is-active", btn.dataset.tab === tab);
      });
      Bridge.send("nav_change", { tab });
      transitioning = false;
    }, TRANSITION_MS);
  }

  window.OGHub = { showView };
})();
