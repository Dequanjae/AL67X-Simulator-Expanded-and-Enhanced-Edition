/**
 * merge.js — Allans fusion grid, reworked to feel Candy-Crush: swap
 * feedback, sparkle/burst on clears, drop-in "fall" for respawned tiles,
 * land-bump on merge results, screen-shake on big combos. Costs Amps
 * (global pool) per merge, delegated entirely to FusionSystem/AmpsService
 * on the GDScript side — this file only renders + sends intents.
 *
 * NOTE ON "GRAVITY": the underlying grid (FusionSystem) resolves matches
 * by respawning freed cells in-place, not by literally shifting a column's
 * stack downward. This file fakes the Candy-Crush "everything above
 * falls" read by animating every changed cell as a clear + drop-from-top,
 * which looks right even though there's no real per-column stack model
 * underneath. A true column-gravity data model would be a larger
 * FusionSystem rework — left as a follow-up if the illusion isn't good
 * enough in practice.
 */
(() => {
  let grid = [];
  let width = 4;
  let height = 4;
  let dragIndex = -1;
  let tileEls = [];
  let mounted = false;

  function root() {
    return document.getElementById("merge-root");
  }

  function ensureMounted() {
    if (mounted) return;
    mounted = true;
    root().innerHTML = `
      <div class="og-merge-header">
        <div class="og-merge-header__portrait" id="og-merge-portrait"></div>
        <div>
          <div class="og-merge-header__name" id="og-merge-name">Allan</div>
          <div class="og-merge-header__owned" id="og-merge-owned">Owned: 1 / 10</div>
        </div>
        <div class="og-merge-amps" id="og-merge-amps"></div>
      </div>
      <div class="og-merge-status" id="og-merge-status">Drag to swap &mdash; line up 3 matching Allans!</div>
      <div class="og-merge-grid" id="og-merge-grid"></div>
      <div class="og-merge-owned-strip" id="og-merge-owned-strip"></div>
    `;
    document.getElementById("og-merge-amps").innerHTML = `${OGIcons.bolt()}<span id="og-merge-amps-text">-/-</span>`;
  }

  function buildGrid() {
    const gridEl = document.getElementById("og-merge-grid");
    gridEl.style.gridTemplateColumns = `repeat(${width}, 68px)`;
    gridEl.innerHTML = "";
    tileEls = [];
    for (let i = 0; i < width * height; i++) {
      const tile = document.createElement("div");
      tile.className = "og-merge-tile";
      tile.dataset.index = String(i);
      const art = document.createElement("div");
      art.className = "og-merge-tile__art";
      tile.appendChild(art);
      tile.addEventListener("pointerdown", () => beginDrag(i));
      tile.addEventListener("pointerenter", () => {
        if (dragIndex >= 0 && dragIndex !== i) attemptSwap(dragIndex, i);
      });
      tile.addEventListener("pointerup", () => endDrag());
      gridEl.appendChild(tile);
      tileEls.push(tile);
    }
    document.addEventListener("pointerup", endDrag);
  }

  function beginDrag(i) {
    dragIndex = i;
    tileEls[i].classList.add("is-dragging");
  }

  function endDrag() {
    if (dragIndex >= 0) tileEls[dragIndex].classList.remove("is-dragging");
    dragIndex = -1;
  }

  function isAdjacent(a, b) {
    const ax = a % width, ay = Math.floor(a / width);
    const bx = b % width, by = Math.floor(b / width);
    return Math.abs(ax - bx) + Math.abs(ay - by) === 1;
  }

  function attemptSwap(a, b) {
    tileEls[a].classList.remove("is-dragging");
    dragIndex = -1;
    if (!isAdjacent(a, b)) return;
    Bridge.send("merge_swap", { a, b });
  }

  function paintTile(i, tier) {
    const art = tileEls[i].querySelector(".og-merge-tile__art");
    const allanId = `player${tier}`;
    OGAllanSheet.applyFrame(art, "idle", 58, OGAllanSheet.sheetPathFor(allanId));
    tileEls[i].title = `Tier ${tier}`;
  }

  function spawnSparkle(tile) {
    for (let i = 0; i < 5; i++) {
      const s = document.createElement("div");
      s.className = "og-merge-sparkle";
      s.innerHTML = OGIcons.sparkle();
      const angle = (Math.PI * 2 * i) / 5;
      s.style.setProperty("--sx", `${Math.cos(angle) * 26}px`);
      s.style.setProperty("--sy", `${Math.sin(angle) * 26}px`);
      s.style.left = "50%";
      s.style.top = "50%";
      tile.appendChild(s);
      setTimeout(() => s.remove(), 500);
    }
  }

  function applyMergeState(data) {
    const newGrid = data.grid || [];
    const merges = data.merges || [];
    const resultIndexes = new Set(merges.map((m) => m.result_index));

    if (!tileEls.length || width !== data.width || height !== data.height) {
      width = data.width || width;
      height = data.height || height;
      buildGrid();
      grid = newGrid;
      grid.forEach((tier, i) => paintTile(i, tier));
      return;
    }

    const changed = [];
    newGrid.forEach((tier, i) => {
      if (grid[i] !== tier) changed.push(i);
    });

    changed.forEach((i) => {
      const tile = tileEls[i];
      tile.classList.add("is-clearing");
      spawnSparkle(tile);
      setTimeout(() => {
        tile.classList.remove("is-clearing");
        paintTile(i, newGrid[i]);
        if (resultIndexes.has(i)) {
          tile.classList.add("is-landed");
          setTimeout(() => tile.classList.remove("is-landed"), 250);
        } else {
          tile.classList.add("is-falling");
          setTimeout(() => tile.classList.remove("is-falling"), 420);
        }
      }, 220);
    });

    grid = newGrid;

    const status = document.getElementById("og-merge-status");
    if (merges.length > 0) {
      const bestTier = Math.max(...merges.map((m) => m.new_tier || 0));
      status.textContent = `Fused into Tier ${bestTier}!`;
      if (merges.length >= 2) {
        const gridEl = document.getElementById("og-merge-grid");
        gridEl.classList.add("is-shaking");
        setTimeout(() => gridEl.classList.remove("is-shaking"), 400);
      }
    } else {
      status.textContent = "Line up 3 matching Allans!";
    }
  }

  function renderAmps(current, max, nextSec) {
    document.getElementById("og-merge-amps-text").textContent = `${current}/${max}`;
    const status = document.getElementById("og-merge-status");
    if (current < 1 && status.textContent.indexOf("AMPS") < 0) {
      status.textContent = "OUT OF AMPS \u2014 wait for a recharge or refill with AL67X";
    }
  }

  function renderCollection(data) {
    document.getElementById("og-merge-owned").textContent = `Owned: ${data.owned.length} / ${data.total}`;
    const equippedEntry = data.owned.find((a) => a.id === data.equipped_id);
    if (equippedEntry) {
      document.getElementById("og-merge-name").textContent = equippedEntry.name || equippedEntry.id;
      OGAllanSheet.applyFrame(
        document.getElementById("og-merge-portrait"),
        "idle",
        60,
        OGAllanSheet.sheetPathFor(equippedEntry.id)
      );
    }
    const strip = document.getElementById("og-merge-owned-strip");
    strip.innerHTML = "";
    data.owned.forEach((allan) => {
      const el = document.createElement("div");
      el.className = `og-merge-owned-item og-pressable ${allan.id === data.equipped_id ? "is-equipped" : ""}`;
      strip.appendChild(el);
      OGAllanSheet.applyFrame(el, "idle", 52, OGAllanSheet.sheetPathFor(allan.id));
      el.addEventListener("click", () => Bridge.send("equip_allan", { allan_id: allan.id }));
    });
  }

  Bridge.on("merge_state", (data) => {
    ensureMounted();
    applyMergeState(data);
  });
  Bridge.on("allan_collection", (data) => {
    ensureMounted();
    renderCollection(data);
  });
  Bridge.on("allan_unlocked", () => Bridge.send("request_allan_collection", {}));
  Bridge.on("amps_changed", (data) => renderAmps(data.current, data.max, data.next_tick_sec));
  Bridge.on("state_sync", (data) => {
    if ("amps" in data) renderAmps(data.amps, data.amps_max, data.amps_next_tick_sec);
  });

  window.addEventListener("DOMContentLoaded", () => {
    ensureMounted();
    Bridge.send("request_merge_state", {});
    Bridge.send("request_allan_collection", {});
  });
})();
