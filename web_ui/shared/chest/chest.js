/**
 * chest.js — chest/loot-box opening popup. Triggered by "chest_opened"
 * (either from a shop purchase auto-open or a future gameplay reward).
 * Animated sequence: lid pops -> light burst -> contents reveal. This is
 * intentionally event-like (auto-plays), never a silent modal.
 */
(() => {
  let mounted = false;

  function ensureMounted() {
    if (mounted) return;
    mounted = true;
    const root = document.getElementById("popup-chest-root");
    root.innerHTML = `
      <div class="og-chest-backdrop" id="og-chest-backdrop">
        <div class="og-chest-stage">
          <div class="og-chest-box" id="og-chest-box">
            <div class="og-chest-box__lid"></div>
            <div class="og-chest-box__base"></div>
            <div class="og-chest-burst"></div>
          </div>
          <div class="og-chest-reveal" id="og-chest-reveal">
            <div class="og-chest-reveal__face" id="og-chest-face"></div>
            <div class="og-chest-reveal__title og-headline og-headline--caution" id="og-chest-title">YOU GOT</div>
            <div class="og-card og-chest-reveal__card" id="og-chest-card"></div>
            <div class="og-chest-reveal__dupe" id="og-chest-dupe"></div>
            <button class="og-btn og-btn--caution og-pressable" id="og-chest-close">NICE!</button>
          </div>
        </div>
      </div>
    `;
    document.getElementById("og-chest-close").addEventListener("click", closePopup);
    OGAllanSheet.applyFrame(document.getElementById("og-chest-face"), "excited", 90);
  }

  function closePopup() {
    const backdrop = document.getElementById("og-chest-backdrop");
    backdrop.classList.remove("is-open");
    document.getElementById("og-chest-box").classList.remove("is-opening");
    document.getElementById("og-chest-reveal").classList.remove("is-shown");
  }

  function play(result) {
    ensureMounted();
    const backdrop = document.getElementById("og-chest-backdrop");
    const box = document.getElementById("og-chest-box");
    const reveal = document.getElementById("og-chest-reveal");
    reveal.classList.remove("is-shown");
    box.classList.remove("is-opening");
    backdrop.classList.add("is-open");

    // Small delay before the pop so the box reads as "arriving", then the
    // lid animation + burst play (CSS), then contents reveal.
    setTimeout(() => box.classList.add("is-opening"), 150);
    setTimeout(() => {
      renderContents(result);
      reveal.classList.add("is-shown");
    }, 650);
  }

  function renderContents(result) {
    const card = document.getElementById("og-chest-card");
    const dupe = document.getElementById("og-chest-dupe");
    const title = document.getElementById("og-chest-title");

    if (!result || result.ok === false) {
      title.textContent = "EMPTY!";
      card.className = "og-card og-chest-reveal__card";
      card.innerHTML = `<div style="text-align:center;font-family:var(--font-voice);font-weight:700;">
        ${result?.reason === "none_owned" ? "No boxes to open." : "Something sparked and fizzled out."}
      </div>`;
      dupe.textContent = "";
      return;
    }

    const cardData = result.card || {};
    const rarity = result.rarity || "common";
    title.textContent = "YOU GOT";
    card.className = `og-card og-chest-reveal__card og-rarity-${rarity}`;
    card.innerHTML = `
      <span class="og-card__rarity-tag">${rarity.toUpperCase()}</span>
      <div style="text-align:center;font-family:var(--font-voice);font-weight:800;font-size:18px;margin-top:8px;">
        ${cardData.name || cardData.id || "???"}
      </div>
      <div style="text-align:center;font-size:12px;opacity:0.75;">${cardData.description || ""}</div>
    `;
    dupe.textContent = result.duplicate ? `DUPLICATE! Owned: x${result.count}` : "NEW CARD!";
  }

  Bridge.on("chest_opened", play);

  window.OGChest = { play };
})();
