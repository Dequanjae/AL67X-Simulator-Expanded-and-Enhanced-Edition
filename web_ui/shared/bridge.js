/**
 * bridge.js — the ONE JS <-> GDScript messaging convention for Overvolt
 * Garage. Every screen imports this and talks to Godot ONLY through
 * `Bridge.send()` / `Bridge.on()`. Never call `ipc.postMessage` directly
 * from screen code — keeps the wire contract in one place so it can be
 * documented, versioned, and swapped to a different transport (see the
 * platform-detection note at the bottom) without touching screen code.
 *
 * Transport today: godot_wry on desktop (`ipc.postMessage` /
 * `document.addEventListener("message", ...)`). On Android/iOS/Web the
 * native host page injects a `window.__OG_TRANSPORT__` shim before this
 * script loads (see src/services/webview_host.gd + addons/webview_mobile);
 * if present we use it instead of `ipc` transparently.
 *
 * ---------------------------------------------------------------------------
 * MESSAGE CONTRACT (mirrors src/autoload/ui_bridge.gd — keep both in sync)
 * ---------------------------------------------------------------------------
 * JS -> Godot ("type" field selects the handler in ui_bridge.gd):
 *   ready                 {screen}                      screen mounted, ask for full state
 *   nav_change            {tab}                         hub bottom/side nav switched
 *   spend_amps            {amount, reason}              gameplay/merge/shop spend request
 *   refill_amps_with_tokens {}                           token top-up (monetization hook)
 *   purchase_loot_box     {box_id}                       shop buy -> hands off to chest popup
 *   open_chest            {box_id}                       consume + roll a box the player owns
 *   purchase_upgrade      {card_id, upgrade_type}        shop card upgrade purchase
 *   purchase_tokens       {pack_id, token_amount}        AL67X Token pack (billing swap-point)
 *   merge_swap            {a, b}                         candy-crush tile swap (indices)
 *   equip_allan           {allan_id}                     equip an owned blob skin
 *   card_choice           {card_id}                      level-up card pick
 *   settings_change       {key, value}                   audio/toggle settings
 *   sign_in / sign_out    {}                              account flow (routes through boot)
 *   open_url              {url}                          external link (Instagram, support)
 *   whats_new_seen        {entry_id}                     mark a news entry as read
 *   debug_add_blobs       {amount}                       DEV ONLY: local swarm-size testing
 *   request_state         {}                              re-sync full state on demand
 *
 * Godot -> JS:
 *   state_sync            {blobs, tokens, amps, amps_max, amps_next_tick_sec,
 *                           level, level_tag, player_name, allan_id, ...}
 *   blobs_changed         {balance, delta}
 *   tokens_changed        {balance}
 *   amps_changed          {current, max, next_tick_sec}
 *   purchase_result       {ok, item_id, reason}
 *   chest_opened          {box_id, contents:[{kind,id,rarity,...}]}
 *   allan_unlocked        {allan_id, tier}
 *   card_unlocked         {card_id, rarity, duplicate, count}
 *   merge_state           {grid, width, height, changed:[...], merges:[...]}
 *   card_choices          {options:[{card_id,...}]}
 *   toast_blobs           {amount, new_total}
 *   whats_new_entries     {entries:[...]}
 * ---------------------------------------------------------------------------
 */

const Bridge = (() => {
  const listeners = new Map(); // type -> Set<fn>
  let ready = false;
  const queue = [];

  // DEV-ONLY: standalone-browser mock replies for request/reply message
  // types, used only when no native transport is attached (see send()).
  // Keep in sync with UIBridge's real reply shapes if either changes.
  const MOCKS = {
    ready: {
      reply: "state_sync",
      data: { blobs: 120, tokens: 40, amps: 7, amps_max: 10, amps_next_tick_sec: 23, level: 3, unseen_news: 1 },
    },
    request_state: {
      reply: "state_sync",
      data: { blobs: 120, tokens: 40, amps: 7, amps_max: 10, amps_next_tick_sec: 23, level: 3, unseen_news: 1 },
    },
    request_shop_catalog: {
      reply: "shop_catalog",
      data: {
        boxes: [
          { id: "basic_box", name: "Basic Loot Box", cost: { currency: "blobs", amount: 100 }, odds_text: "common 70% / rare 25% / epic 5%", drops: [{ rarity: "common", weight: 70 }, { rarity: "rare", weight: 25 }, { rarity: "epic", weight: 5 }] },
          { id: "premium_box", name: "Premium Loot Box", cost: { currency: "tokens", amount: 50 }, odds_text: "common 30% / rare 40% / epic 24% / legendary 6%", drops: [{ rarity: "legendary", weight: 6 }] },
        ],
        upgrades: [
          { card_id: "goon_launcher", name: "Goon Launcher", rarity: "epic", upgrades: [{ type: "damage", level: 2, cost: { currency: "blobs", amount: 140 } }, { type: "projectiles", level: 0, cost: { currency: "tokens", amount: 50 } }] },
        ],
        tokens: 40,
        blobs: 120,
      },
    },
    request_settings: {
      reply: "settings_state",
      data: { music_volume: 1, sfx_volume: 0.8, screen_shake: 1, camera_smoothing: true, goo_splats: true, damage_numbers: true, save_mode: "" },
    },
    request_whats_new: {
      reply: "whats_new_entries",
      data: { entries: [{ id: "mock-1", date: "2026-07-01", title: "Mock Update (browser preview)", body: "This entry only shows up when no Godot backend is attached.", image: "" }], unseen_count: 1 },
    },
    request_merge_state: {
      reply: "merge_state",
      data: { grid: [1, 1, 2, 1, 3, 4, 1, 3, 4, 3, 4, 5, 5, 6, 5, 6], width: 4, height: 4, merges: [] },
    },
    request_allan_collection: {
      reply: "allan_collection",
      data: {
        equipped_id: "player1",
        owned: [{ id: "player1", name: "Allan", tier: 1 }, { id: "player2", name: "Allan II", tier: 2 }],
        total: 10,
      },
    },
  };

  function _transportSend(msg) {
    if (window.__OG_TRANSPORT__ && window.__OG_TRANSPORT__.postMessage) {
      window.__OG_TRANSPORT__.postMessage(msg);
      return true;
    }
    // gdcef (desktop backend, see webview_host.gd's _mount_cef_desktop):
    // GDScript registers a method named exactly `_on_cef_ipc_message`,
    // callable from JS as window.godotMethods._on_cef_ipc_message(...).
    if (window.godotMethods && window.godotMethods._on_cef_ipc_message) {
      window.godotMethods._on_cef_ipc_message(msg);
      return true;
    }
    if (window.ipc && window.ipc.postMessage) {
      window.ipc.postMessage(msg);
      return true;
    }
    return false;
  }

  function send(type, payload = {}) {
    const msg = JSON.stringify({ type, ...payload });
    if (!_transportSend(msg)) {
      // No native host (e.g. iterating on the HTML in a plain desktop
      // browser tab, which is how every screen in this repo was actually
      // visually verified). Serve a DEV-ONLY mock reply for known
      // request/reply message types so screens still render with
      // representative data instead of staying blank — see MOCKS below.
      // Queue too, for visibility in the console.
      queue.push(msg);
      const mock = MOCKS[type];
      if (mock) {
        setTimeout(() => _dispatch({ type: mock.reply, ...mock.data }), 30);
      } else {
        console.warn("[Bridge] no transport available, queued:", msg);
      }
    }
  }

  function on(type, handler) {
    if (!listeners.has(type)) listeners.set(type, new Set());
    listeners.get(type).add(handler);
    return () => listeners.get(type).delete(handler);
  }

  function _dispatch(data) {
    if (!data || !data.type) return;
    const set = listeners.get(data.type);
    if (set) set.forEach((fn) => fn(data));
    const wildcard = listeners.get("*");
    if (wildcard) wildcard.forEach((fn) => fn(data));
  }

  function _handleRaw(raw) {
    let data;
    try {
      data = JSON.parse(raw);
    } catch (e) {
      return;
    }
    _dispatch(data);
  }

  // `message` is the DOM event convention this bridge uses for the
  // Godot -> JS direction regardless of which native backend (if any) is
  // attached. `og-message` is the fallback custom event mobile/Web shims
  // dispatch (see webview_host.gd) — screen code never needs to know
  // which one fired.
  document.addEventListener("message", (event) => _handleRaw(event.detail));
  window.addEventListener("og-message", (event) => _dispatch(event.detail));

  // gdcef (desktop): GDScript sends via `browser.emit_js("message", json)`,
  // delivered to a global `window.godotEvents` gdcef injects itself into
  // every page it renders — poll briefly for it since it may not exist
  // the instant this script runs.
  (function waitForGodotEvents(triesLeft) {
    if (window.godotEvents && window.godotEvents.on) {
      window.godotEvents.on("message", (json) => _handleRaw(json));
      return;
    }
    if (triesLeft > 0) setTimeout(() => waitForGodotEvents(triesLeft - 1), 50);
  })(40);

  window.addEventListener("DOMContentLoaded", () => {
    ready = true;
  });

  return { send, on };
})();

window.Bridge = Bridge;
