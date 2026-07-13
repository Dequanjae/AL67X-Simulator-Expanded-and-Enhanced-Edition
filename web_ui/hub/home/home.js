/**
 * home.js — Home Dashboard logic. Talks to Godot ONLY through Bridge.
 * Owns: resource pill rendering, floating blob swarm (count == real Blob
 * balance, capped for perf), Amps countdown ring, Ignition CTA spark burst,
 * character level tag/name plate.
 */
(() => {
  const MAX_SWARM = 40;

  const state = {
    blobs: 0,
    tokens: 0,
    amps: 0,
    ampsMax: 0,
    ampsNextTickSec: -1,
    level: 1,
    unseenNews: 0,
  };

  let ampsTickHandle = null;

  function $(id) {
    return document.getElementById(id);
  }

  function injectStaticIcons() {
    $("icon-tokens").innerHTML = OGIcons.token();
    $("icon-amps").innerHTML = OGIcons.bolt();
    $("icon-wrench").innerHTML = OGIcons.wrench();
    $("icon-badge-bolt").innerHTML = OGIcons.bolt();
    $("icon-cta-bolt").innerHTML = OGIcons.bolt();
    $("btn-news").innerHTML = OGIcons.news();
    $("btn-mail").innerHTML = OGIcons.mail();
    $("btn-settings").innerHTML = OGIcons.gear();
    document.querySelectorAll(".og-nav-badge__icon").forEach((el) => {
      const name = el.parentElement.dataset.tab;
      const map = { home: "home", deck: "cards", merge: "merge", shop: "shop" };
      const fn = OGIcons[map[name]];
      if (fn) el.innerHTML = fn();
    });
  }

  function renderStats() {
    $("stat-blobs").textContent = state.blobs;
    $("stat-tokens").textContent = state.tokens;
    $("stat-amps").textContent = `${state.amps}/${state.ampsMax}`;
    $("level-pill").textContent = `LV ${state.level} \u00B7 SHOP TECH`;
    renderNewsDot();
  }

  function renderNewsDot() {
    const btn = $("btn-news");
    let dot = btn.querySelector(".og-icon-btn__dot");
    if (state.unseenNews > 0) {
      if (!dot) {
        dot = document.createElement("span");
        dot.className = "og-icon-btn__dot";
        btn.appendChild(dot);
      }
    } else if (dot) {
      dot.remove();
    }
  }

  // ---- Amps countdown ring --------------------------------------------------
  const RING_CIRC = 2 * Math.PI * 15; // r=15 per the SVG circle
  const AMPS_REGEN_SEC = 45;

  function renderAmpsRing() {
    const ring = $("amps-ring-fg");
    if (state.amps >= state.ampsMax || state.ampsNextTickSec < 0) {
      ring.style.strokeDashoffset = "0";
      return;
    }
    const progress = 1 - state.ampsNextTickSec / AMPS_REGEN_SEC;
    ring.style.strokeDashoffset = String(RING_CIRC * (1 - progress));
  }

  function startAmpsTicker() {
    if (ampsTickHandle) clearInterval(ampsTickHandle);
    ampsTickHandle = setInterval(() => {
      if (state.amps >= state.ampsMax) return;
      if (state.ampsNextTickSec > 0) {
        state.ampsNextTickSec -= 1;
        renderAmpsRing();
      }
    }, 1000);
  }

  // ---- Floating blob swarm ---------------------------------------------------
  function renderSwarm() {
    const root = $("blob-swarm");
    const target = Math.min(state.blobs, MAX_SWARM);
    const current = root.children.length;

    if (target > current) {
      for (let i = current; i < target; i++) {
        root.appendChild(makeSwarmMember());
      }
    } else if (target < current) {
      for (let i = current - 1; i >= target; i--) {
        root.removeChild(root.children[i]);
      }
    }
  }

  function makeSwarmMember() {
    const el = document.createElement("div");
    el.className = "og-blob-avatar";
    const img = document.createElement("img");
    img.src = OGAssets.resolve("../../assets/sprites/allan/frames/player_idle0.png");
    el.appendChild(img);

    const x = 4 + Math.random() * 92;
    const y = 8 + Math.random() * 78;
    el.style.left = `${x}%`;
    el.style.top = `${y}%`;

    const dx = (Math.random() - 0.5) * 40;
    const dy = (Math.random() - 0.5) * 40;
    const dr = (Math.random() - 0.5) * 20;
    el.style.setProperty("--dx", `${dx}px`);
    el.style.setProperty("--dy", `${dy}px`);
    el.style.setProperty("--dr", `${dr}deg`);
    el.style.animationDuration = `${4 + Math.random() * 4}s`;
    el.style.animationDelay = `${Math.random() * -6}s`;
    el.style.opacity = String(0.55 + Math.random() * 0.35);
    return el;
  }

  // ---- Ignition CTA spark burst ---------------------------------------------
  function spawnSparks(originEl) {
    const rect = originEl.getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;
    for (let i = 0; i < 8; i++) {
      const spark = document.createElement("div");
      spark.className = "og-spark";
      const angle = (Math.PI * 2 * i) / 8 + Math.random() * 0.3;
      const dist = 36 + Math.random() * 24;
      spark.style.setProperty("--sx", `${Math.cos(angle) * dist}px`);
      spark.style.setProperty("--sy", `${Math.sin(angle) * dist}px`);
      spark.style.left = `${cx}px`;
      spark.style.top = `${cy}px`;
      document.body.appendChild(spark);
      setTimeout(() => spark.remove(), 550);
    }
  }

  // ---- Warp zone teleport (plays before handing off to the real run) --------
  function playWarpAndStartRun() {
    const warp = $("og-warp");
    warp.classList.add("is-active");
    $("btn-ignition").disabled = true;
    setTimeout(() => {
      Bridge.send("start_run", {});
      // Leave it active — the scene is about to swap out from under us via
      // SceneManager's own transition, so no need to reset the class here.
    }, 850);
  }

  // ---- Wire up ----------------------------------------------------------------
  function bindEvents() {
    $("pill-blobs").addEventListener("click", () => {
      // Dev-only local swarm testing hook, per spec. Not a shipped player
      // interaction — harmless no-op if Godot ignores/rejects it in release.
      Bridge.send("debug_add_blobs", { amount: 1 });
    });

    $("btn-ignition").addEventListener("click", (e) => {
      spawnSparks(e.currentTarget);
      playWarpAndStartRun();
    });

    $("btn-news").addEventListener("click", () => Bridge.send("open_news", {}));
    $("btn-mail").addEventListener("click", () => Bridge.send("open_mail", {}));
    $("btn-settings").addEventListener("click", () => window.OGHub && window.OGHub.showView("settings"));

    document.querySelectorAll(".og-nav-badge").forEach((btn) => {
      btn.addEventListener("click", () => {
        const tab = btn.dataset.tab;
        window.OGHub && window.OGHub.showView(tab);
      });
    });
  }

  function applyStateSync(data) {
    if ("blobs" in data) state.blobs = data.blobs;
    if ("tokens" in data) state.tokens = data.tokens;
    if ("amps" in data) state.amps = data.amps;
    if ("amps_max" in data) state.ampsMax = data.amps_max;
    if ("amps_next_tick_sec" in data) state.ampsNextTickSec = data.amps_next_tick_sec;
    if ("level" in data) state.level = data.level;
    if ("unseen_news" in data) state.unseenNews = data.unseen_news;
    renderStats();
    renderSwarm();
    renderAmpsRing();
  }

  Bridge.on("state_sync", applyStateSync);
  Bridge.on("blobs_changed", (data) => {
    state.blobs = data.balance;
    renderStats();
    renderSwarm();
  });
  Bridge.on("tokens_changed", (data) => {
    state.tokens = data.balance;
    renderStats();
  });
  Bridge.on("amps_changed", (data) => {
    state.amps = data.current;
    state.ampsMax = data.max;
    state.ampsNextTickSec = data.next_tick_sec;
    renderStats();
    renderAmpsRing();
  });

  window.addEventListener("DOMContentLoaded", () => {
    injectStaticIcons();
    bindEvents();
    startAmpsTicker();
    Bridge.send("ready", { screen: "home" });
  });
})();
