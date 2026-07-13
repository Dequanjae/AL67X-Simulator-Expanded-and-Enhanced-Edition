/**
 * card_select.js — level-up card choice (2-4 options). Triggered by
 * "card_choices" (UIBridge relays EventBus.card_choice_presented). Picking
 * sends "card_choice" back; the level-up system applies the effect and the
 * run un-pauses on the GDScript side.
 */
(() => {
  let mounted = false;

  function ensureMounted() {
    if (mounted) return;
    mounted = true;
    const root = document.getElementById("popup-cardselect-root");
    root.innerHTML = `
      <div class="og-cardselect-backdrop" id="og-cardselect-backdrop">
        <div class="og-cardselect-panel">
          <div class="og-cardselect-title og-headline og-headline--volt">LEVEL UP!</div>
          <div class="og-cardselect-row" id="og-cardselect-row"></div>
        </div>
      </div>
    `;
  }

  function open(options) {
    ensureMounted();
    const row = document.getElementById("og-cardselect-row");
    row.innerHTML = "";
    (options || []).forEach((card) => {
      const rarity = card.rarity || "common";
      const el = document.createElement("div");
      el.className = `og-card og-cardselect-card og-rarity-${rarity} og-tilt-${Math.random() > 0.5 ? "l" : "r"}`;
      el.innerHTML = `
        <span class="og-card__rarity-tag">${rarity.toUpperCase()}</span>
        <div class="og-cardselect-card__icon">${OGIcons.sparkle()}</div>
        <div class="og-cardselect-card__name">${card.name || card.id}</div>
        <div class="og-cardselect-card__desc">${card.description || ""}</div>
      `;
      el.addEventListener("click", () => pick(card.id, el, row));
      row.appendChild(el);
    });
    document.getElementById("og-cardselect-backdrop").classList.add("is-open");
  }

  function pick(cardId, pickedEl, row) {
    Array.from(row.children).forEach((child) => {
      child.classList.add(child === pickedEl ? "is-picked" : "is-unpicked");
      child.style.pointerEvents = "none";
    });
    Bridge.send("card_choice", { card_id: cardId });
    setTimeout(() => {
      document.getElementById("og-cardselect-backdrop").classList.remove("is-open");
    }, 550);
  }

  Bridge.on("card_choices", (data) => open(data.options));

  window.OGCardSelect = { open };
})();
