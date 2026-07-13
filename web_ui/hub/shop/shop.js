/**
 * shop.js — Shop screen. Loot boxes (buy -> hands off into chest popup,
 * per spec) + card upgrades + AL67X token packs. Data comes from
 * UIBridge's "shop_catalog" message; this file only renders + sends intents.
 */
(() => {
  const root = () => document.getElementById("shop-root");

  function rarityClass(rarity) {
    return `og-rarity-${rarity || "common"}`;
  }

  function bestRarity(drops) {
    const order = ["legendary", "epic", "rare", "common"];
    const present = new Set((drops || []).map((d) => d.rarity));
    return order.find((r) => present.has(r)) || "common";
  }

  function renderBoxCard(box) {
    const el = document.createElement("div");
    el.className = `og-card og-box-card ${rarityClass(bestRarity(box.drops))}`;
    const currency = box.cost?.currency === "tokens" ? "token" : null;
    el.innerHTML = `
      <span class="og-card__rarity-tag">${bestRarity(box.drops).toUpperCase()}</span>
      <div class="og-box-card__art">${OGIcons.chest()}</div>
      <div class="og-box-card__name">${box.name || box.id}</div>
      <div class="og-box-card__odds">${box.odds_text || ""}</div>
      <div class="og-price-tag">
        ${currency ? OGIcons.token() : `<img src="${OGAssets.resolve("../../assets/sprites/allan/frames/player_idle0.png")}" style="width:16px;height:16px;object-fit:contain;" />`}
        ${box.cost?.amount ?? 0}
      </div>
      <button class="og-btn og-btn--caution og-pressable" data-buy="${box.id}">BUY</button>
    `;
    el.querySelector("[data-buy]").addEventListener("click", () => {
      Bridge.send("purchase_loot_box", { box_id: box.id });
    });
    return el;
  }

  function renderUpgradeRow(entry) {
    const el = document.createElement("div");
    el.className = "og-upgrade-row";
    const chips = (entry.upgrades || [])
      .map((u) => {
        const currency = u.cost?.currency === "tokens" ? "AL67X" : "Blobs";
        return `
        <div class="og-upgrade-chip">
          <span class="og-upgrade-chip__label">${u.type}</span>
          <button class="og-btn og-btn--ghost og-pressable" style="font-size:11px;padding:6px 10px;"
            data-upgrade="${entry.card_id}" data-type="${u.type}">
            Lv ${u.level} &rarr; ${u.cost?.amount ?? 0} ${currency}
          </button>
        </div>`;
      })
      .join("");
    el.innerHTML = `<span class="og-upgrade-row__name">${entry.name}</span>${chips}`;
    el.querySelectorAll("[data-upgrade]").forEach((btn) => {
      btn.addEventListener("click", () => {
        Bridge.send("purchase_upgrade", {
          card_id: btn.dataset.upgrade,
          upgrade_type: btn.dataset.type,
        });
      });
    });
    return el;
  }

  function render(catalog) {
    const r = root();
    r.innerHTML = "";

    const header = document.createElement("div");
    header.className = "og-shop-header";
    header.innerHTML = `
      <img src="${OGAssets.resolve("../../assets/sprites/npc/allan_shopkeeper.png")}" alt="" />
      <div>
        <h1 class="og-headline og-headline--safety" style="font-size:32px;margin:0;">SHOP</h1>
        <div class="og-shop-header__title">Allan the shop bender</div>
      </div>
    `;
    r.appendChild(header);

    const boxTitle = document.createElement("div");
    boxTitle.className = "og-shop-section-title";
    boxTitle.textContent = "LOOT BOXES";
    r.appendChild(boxTitle);

    const boxGrid = document.createElement("div");
    boxGrid.className = "og-shop-grid";
    (catalog.boxes || []).forEach((box) => boxGrid.appendChild(renderBoxCard(box)));
    r.appendChild(boxGrid);

    if ((catalog.upgrades || []).length) {
      const upgTitle = document.createElement("div");
      upgTitle.className = "og-shop-section-title";
      upgTitle.textContent = "CARD UPGRADES";
      r.appendChild(upgTitle);

      const upgList = document.createElement("div");
      catalog.upgrades.forEach((entry) => upgList.appendChild(renderUpgradeRow(entry)));
      r.appendChild(upgList);
    }
  }

  Bridge.on("shop_catalog", render);

  window.addEventListener("DOMContentLoaded", () => {
    Bridge.send("request_shop_catalog", {});
  });
})();
