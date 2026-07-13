/**
 * settings.js — quieter settings sheet: audio sliders, toggles, account,
 * version footer. Talks to Godot's GameSettings via settings_change.
 */
(() => {
  const root = () => document.getElementById("settings-root");
  let state = {};

  function slider(key, label) {
    const val = Math.round((state[key] ?? 1) * 100);
    return `
      <div class="og-settings-row">
        <span class="og-settings-row__label">${label}</span>
        <input type="range" min="0" max="100" step="5" value="${val}" data-slider="${key}" />
      </div>`;
  }

  function toggle(key, label) {
    const on = !!state[key];
    return `
      <div class="og-settings-row">
        <span class="og-settings-row__label">${label}</span>
        <div class="og-toggle ${on ? "is-on" : ""}" data-toggle="${key}">
          <div class="og-toggle__knob"></div>
        </div>
      </div>`;
  }

  function render() {
    const r = root();
    const signedIn = state.save_mode === "cloud";
    r.innerHTML = `
      <div class="og-settings-panel">
        <div class="og-settings-title og-headline og-headline--volt">SETTINGS</div>
        ${slider("music_volume", "Music")}
        ${slider("sfx_volume", "Sound FX")}
        ${slider("screen_shake", "Screen Shake")}
        ${toggle("camera_smoothing", "Camera Smoothing")}
        ${toggle("goo_splats", "Goo Splats")}
        ${toggle("damage_numbers", "Damage Numbers")}
        <div class="og-settings-account">
          <span class="og-settings-row__label">${signedIn ? "Signed in with Google" : "Local save"}</span>
          <button class="og-btn ${signedIn ? "og-btn--ghost" : "og-btn--volt"} og-pressable" id="btn-account">
            ${signedIn ? "Sign Out" : "Sign in with Google"}
          </button>
        </div>
        <button class="og-btn og-pressable" id="btn-settings-close" style="width:100%;margin-top:16px;">DONE</button>
        <div class="og-settings-footer">Overvolt Garage &middot; AL67X Simulator</div>
      </div>
    `;

    r.querySelectorAll("[data-slider]").forEach((input) => {
      input.addEventListener("input", () => {
        const key = input.dataset.slider;
        const value = Number(input.value) / 100;
        state[key] = value;
        Bridge.send("settings_change", { key, value });
      });
    });

    r.querySelectorAll("[data-toggle]").forEach((el) => {
      el.addEventListener("click", () => {
        const key = el.dataset.toggle;
        const value = !state[key];
        state[key] = value;
        el.classList.toggle("is-on", value);
        Bridge.send("settings_change", { key, value });
      });
    });

    const account = r.querySelector("#btn-account");
    account.addEventListener("click", () => {
      Bridge.send(signedIn ? "sign_out" : "sign_in", {});
    });

    r.querySelector("#btn-settings-close").addEventListener("click", () => {
      window.OGHub && window.OGHub.showView("home");
    });
  }

  Bridge.on("settings_state", (data) => {
    state = data;
    render();
  });

  window.addEventListener("DOMContentLoaded", () => {
    Bridge.send("request_settings", {});
  });
})();
