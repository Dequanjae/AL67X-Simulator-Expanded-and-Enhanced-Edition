/**
 * blob_toast.js — "Blobs You Rescued" toast. Whenever blobs are earned
 * (gameplay/chests/anything -> UIBridge broadcasts "toast_blobs"), a few
 * mini blob avatars fly in from random screen edges and "get collected"
 * into the toast pill while the count tweens up from the old total to the
 * new one. Never snaps the number.
 */
(() => {
  let mounted = false;
  let displayedTotal = null; // lazily initialized from the first state_sync
  let tweenHandle = null;

  function ensureMounted() {
    if (mounted) return;
    mounted = true;
    const root = document.getElementById("popup-blobtoast-root");
    root.innerHTML = `
      <div class="og-blobtoast" id="og-blobtoast">
        <span class="og-blobtoast__icon"><img src="${OGAssets.resolve("../../assets/sprites/allan/frames/player_idle0.png")}" alt="" /></span>
        <span class="og-blobtoast__body">
          <span class="og-blobtoast__label">Blobs You Rescued</span>
          <span class="og-blobtoast__count" id="og-blobtoast-count">0</span>
        </span>
      </div>
    `;
  }

  function flyMini(toastRect) {
    const el = document.createElement("div");
    el.className = "og-blobtoast__mini-fly";
    el.innerHTML = `<img src="${OGAssets.resolve("../../assets/sprites/allan/frames/player_idle0.png")}" alt="" />`;
    const fromX = Math.random() * window.innerWidth;
    const fromY = Math.random() < 0.5 ? -30 : window.innerHeight + 30;
    el.style.left = `${fromX}px`;
    el.style.top = `${fromY}px`;
    document.body.appendChild(el);
    requestAnimationFrame(() => {
      el.style.left = `${toastRect.left + toastRect.width * 0.15}px`;
      el.style.top = `${toastRect.top + toastRect.height * 0.5}px`;
      el.style.opacity = "0.2";
      el.style.transform = "scale(0.4)";
    });
    setTimeout(() => el.remove(), 600);
  }

  function tweenCount(from, to, ms = 650) {
    if (tweenHandle) cancelAnimationFrame(tweenHandle);
    const start = performance.now();
    const el = document.getElementById("og-blobtoast-count");
    function step(now) {
      const t = Math.min(1, (now - start) / ms);
      const eased = 1 - Math.pow(1 - t, 3);
      el.textContent = Math.round(from + (to - from) * eased);
      if (t < 1) {
        tweenHandle = requestAnimationFrame(step);
      } else {
        el.textContent = to;
      }
    }
    tweenHandle = requestAnimationFrame(step);
  }

  function show(amount, newTotal) {
    ensureMounted();
    const toast = document.getElementById("og-blobtoast");
    const from = displayedTotal === null ? Math.max(0, newTotal - amount) : displayedTotal;
    displayedTotal = newTotal;

    toast.classList.add("is-shown");
    const rect = toast.getBoundingClientRect();
    const flies = Math.max(1, Math.min(6, amount));
    for (let i = 0; i < flies; i++) {
      setTimeout(() => flyMini(rect), i * 60);
    }
    tweenCount(from, newTotal);

    clearTimeout(show._hideTimer);
    show._hideTimer = setTimeout(() => toast.classList.remove("is-shown"), 2200);
  }

  Bridge.on("toast_blobs", (data) => show(data.amount, data.new_total));
  Bridge.on("state_sync", (data) => {
    if (displayedTotal === null && "blobs" in data) displayedTotal = data.blobs;
  });

  window.OGBlobToast = { show };
})();
