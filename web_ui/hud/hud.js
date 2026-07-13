/**
 * hud.js — in-run HUD, restyled to match the design system. Pure
 * presentation; all gameplay state (hearts, timer, XP, boss, banking)
 * still lives in run_controller.gd, which broadcasts "run_hud_state" +
 * dedicated event messages ("player_died", "player_revived",
 * "run_ascend"). Card-choice level-up reuses the shared card_select popup
 * unchanged. Death spotlight stays a native Godot shader on the 3D world
 * (can't be done in HTML since it darkens the game view, not UI chrome) —
 * this file only shows the death PANEL content on top of it.
 */
(() => {
  let paused = false;

  function $(id) {
    return document.getElementById(id);
  }

  function renderHearts(hearts, maxHearts, shield) {
    const box = $("hud-hearts");
    const wanted = maxHearts + shield;
    if (box.children.length !== wanted) {
      box.innerHTML = "";
      for (let i = 0; i < wanted; i++) {
        const el = document.createElement("span");
        el.className = "og-hud-heart";
        box.appendChild(el);
      }
    }
    for (let i = 0; i < box.children.length; i++) {
      if (i < maxHearts) {
        box.children[i].innerHTML = OGIcons.heart(i < hearts);
      } else {
        box.children[i].innerHTML = OGIcons.shield();
      }
    }
  }

  function applyState(data) {
    renderHearts(data.hearts, data.max_hearts, data.shield);
    $("hud-timer").textContent = data.timer_text;
    $("hud-blobs").textContent = data.blobs;
    $("hud-level").textContent = `Lv ${data.level}`;
    const pct = data.xp_max > 0 ? Math.min(100, (data.xp / data.xp_max) * 100) : 0;
    $("hud-xp-fill").style.width = `${pct}%`;

    $("hud-boss-warn").classList.toggle("is-shown", !!data.boss_warning);

    const bossWrap = $("hud-boss-bar-wrap");
    bossWrap.classList.toggle("is-shown", !!data.boss_active);
    if (data.boss_active) {
      $("hud-boss-name").textContent = data.boss_name || "BOSS";
      $("hud-boss-fill").style.width = `${Math.round((data.boss_hp_ratio || 0) * 100)}%`;
    }

    $("hud-dev").classList.toggle("is-shown", !!data.dev_mode);
    $("hud-ad-continue").disabled = !!data.ad_used;
    $("hud-ad-continue").textContent = data.ad_used ? "Ad continue used" : "Watch ad to continue";
  }

  function showDeath(data) {
    OGAllanSheet.applyFrame($("hud-death-face"), "cry", 160, OGAllanSheet.sheetPathFor(data.allan_id || "player1"));
    $("hud-death-backdrop").classList.add("is-shown");
  }

  function hideDeath() {
    $("hud-death-backdrop").classList.remove("is-shown");
  }

  function tweenAscendCount(from, to, ms, onDone) {
    const start = performance.now();
    function step(now) {
      const t = Math.min(1, (now - start) / ms);
      const eased = 1 - Math.pow(1 - t, 3);
      const counted = Math.round(from + (to - from) * eased);
      $("hud-ascend-count").textContent = `+${counted} Blobs`;
      if (t < 1) {
        requestAnimationFrame(step);
      } else {
        $("hud-ascend-count").textContent = `+${to - from} Blobs`;
        $("hud-ascend-total").textContent = `Total: ${to}`;
        if (onDone) onDone();
      }
    }
    requestAnimationFrame(step);
  }

  function showAscend(data) {
    hideDeath();
    $("hud-ascend-title").textContent = data.victory
      ? `DAY ${data.level} COMPLETE!`
      : "ASCENDING TO HEAVEN...";
    $("hud-ascend-count").textContent = "+0 Blobs";
    $("hud-ascend-total").textContent = `Total: ${data.total_before}`;
    $("hud-ascend-overlay").classList.add("is-shown");
    const duration = Math.min(1600, Math.max(500, 300 + data.run_blobs * 12));
    tweenAscendCount(data.total_before, data.total_after, duration);
  }

  function bindEvents() {
    $("hud-dev-win").addEventListener("click", () => Bridge.send("dev_boss_win", {}));
    $("hud-dev-die").addEventListener("click", () => Bridge.send("dev_die", {}));
    $("hud-ad-continue").addEventListener("click", () => Bridge.send("ad_continue", {}));
    $("hud-ascend").addEventListener("click", () => Bridge.send("ascend_continue", {}));

    $("hud-pause-btn").addEventListener("click", () => {
      paused = !paused;
      $("hud-pause-backdrop").classList.toggle("is-shown", paused);
      Bridge.send("pause_toggle", { paused });
    });
    $("hud-resume").addEventListener("click", () => {
      paused = false;
      $("hud-pause-backdrop").classList.remove("is-shown");
      Bridge.send("pause_toggle", { paused: false });
    });
    $("hud-quit-hub").addEventListener("click", () => Bridge.send("quit_to_hub", {}));
  }

  Bridge.on("run_hud_state", applyState);
  Bridge.on("player_died", showDeath);
  Bridge.on("player_revived", hideDeath);
  Bridge.on("run_ascend", showAscend);

  window.addEventListener("DOMContentLoaded", () => {
    $("hud-pause-btn").innerHTML = OGIcons.pause();
    bindEvents();
    Bridge.send("ready", { screen: "hud" });
  });
})();
