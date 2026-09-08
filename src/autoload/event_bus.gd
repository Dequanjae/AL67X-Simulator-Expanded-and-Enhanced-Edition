extends Node
## EventBus — global cross-system signal contract (autoload).
##
## This file IS the contract layer (spec Section 10). Systems communicate
## through these signals instead of holding references to each other.
## Rules:
##  - Every signal documents WHO emits it and WHO is expected to listen.
##  - Systems must not emit signals owned by another system (e.g. only
##    EconomyService emits blobs_changed/tokens_changed).
##  - Adding a signal here is an architecture decision — keep this file the
##    single source of truth, and keep it documented.

# ---------------------------------------------------------------------------
# RUN LIFECYCLE — emitted by the Run controller (run scene)
# Listeners: HUD, AudioDirector, SaveService-adjacent banking, analytics.
# ---------------------------------------------------------------------------

## A run has begun on the given level.
signal run_started(level: int)

## The run is over (ascend after death, or victory after boss kill).
## summary = {
##   "level": int, "victory": bool, "blobs_banked": int,
##   "duration_sec": float, "reason": String  # "ascend" | "boss_defeated"
## }
## Banking of run currency into permanent balances is done BY the run/death
## controller (via EconomyService) BEFORE this fires; listeners treat this
## as informational.
signal run_ended(summary: Dictionary)

## Survival timer reached zero → boss phase imminent. HUD shows warning.
signal boss_incoming(level: int)

## Boss actually spawned into the arena.
signal boss_spawned(boss_id: String)

## Boss killed. Run controller reacts by unlocking the next level.
signal boss_defeated(boss_id: String, level: int)

## Permanent progress: a new level became available (persists regardless of
## how the run ends afterwards). Emitted by the run controller after writing
## to SaveService.
signal level_unlocked(level: int)

# ---------------------------------------------------------------------------
# WORLDGEN / PICKUPS — emitted by pickup & spawner systems during a run
# Listeners: Run controller (in-run counters + blob swarm), AudioDirector,
# VFX. NOTE: these are IN-RUN amounts, not permanent balances — permanent
# balances change only at banking time (run end) through EconomyService.
# ---------------------------------------------------------------------------

## Player ate a Shawarma/Doinair: +amount in-run blobs; swarm spawns
## `amount` Mini-Allans to stay in sync with the numeric count.
signal blob_collected(amount: int)

## An enemy touched a Mini-Allan: -amount in-run blobs; swarm despawns the
## member and does the scatter/flinch burst.
signal blob_lost(amount: int)

## Rarity-tiered map powerup grabbed.
signal powerup_picked_up(powerup_id: String)

## A free loot box spawned somewhere on the map (HUD may ping it).
signal loot_box_spawned(world_position: Vector3)

## Player grabbed a map loot box; Card system rolls and grants contents.
signal loot_box_collected(loot_box_id: String)

# ---------------------------------------------------------------------------
# PLAYER / IN-RUN LEVELING — emitted by the Player/XP system
# ---------------------------------------------------------------------------

## In-run level increased. Card system listens → pauses & presents the
## 1-of-3 card choice menu.
signal player_leveled_up(new_level: int)

## Card system announced the 3 offered options (HUD renders them).
## options = Array of card ids.
signal card_choice_presented(options: Array)

## Player picked a card from the 1-of-3 menu; combat system applies effect.
signal card_chosen(card_id: String)

## Player HP hit zero. Death/ascend sequence controller listens: freeze,
## spotlight, death music, ad-continue prompt.
signal player_died()

## Ad-continue succeeded → unfreeze and resume the run.
signal player_revived()

# ---------------------------------------------------------------------------
# COMBAT FEEDBACK — emitted by combat systems; AudioDirector + VFX listen.
# Each has a DISTINCT audio identity (hit-feel priority, spec Section 11).
# ---------------------------------------------------------------------------

signal enemy_hit(enemy_id: String, damage: float, world_pos: Vector3)
signal enemy_killed(enemy_id: String, world_pos: Vector3)
signal player_hit(damage: float)
signal blob_follower_hit()

## Aura Shield absorbed a hit and broke (one-time shields, no regen).
signal shield_broken()

# ---------------------------------------------------------------------------
# ECONOMY (PERMANENT BALANCES) — emitted ONLY by EconomyService
# Listeners: hub top bar, shop screens, ascend count-up animation.
# ---------------------------------------------------------------------------

signal blobs_changed(new_balance: int)
signal tokens_changed(new_balance: int)

## Watts balance changed (EconomyService/WattsService emit; hub top bar
## listens). Watts accrue in real time — the first read after load syncs.
signal watts_changed(new_balance: int)
## Gems balance changed (EconomyService emits; gems top bar listens).
signal gems_changed(new_balance: int)
signal purchase_completed(item_id: String)
signal purchase_failed(item_id: String, reason: String)

# ---------------------------------------------------------------------------
# COLLECTION / META — emitted by Allan fusion & Card systems
# ---------------------------------------------------------------------------

## New Allan skin created via fusion (or otherwise granted). Triggers the
## over-the-top "New Allan!" reveal.
signal allan_unlocked(allan_id: String)
signal allan_equipped(allan_id: String)

## Amps (global real-time energy/stamina pool) changed — regen tick, spend,
## refund, or token top-up. Emitted ONLY by AmpsService. Any spender
## (merge minigame, future gameplay/shop systems) calls AmpsService.spend()
## rather than touching SaveService directly.
signal amps_changed(current: int, maximum: int)

signal card_unlocked(card_id: String)
signal deck_changed(equipped: Array)

# ---------------------------------------------------------------------------
# SAVE / CLOUD — emitted by SaveService
# ---------------------------------------------------------------------------

## In-memory save data replaced (initial load or cloud overwrite) — UI
## should re-read everything it displays.
signal save_loaded()

## A settings value changed (key under meta.settings). Systems re-apply.
signal settings_changed(key: String, value: Variant)

## Data flushed to disk.
signal save_committed()

## Cloud sync state: "disabled" | "signed_out" | "syncing" | "synced" | "error"
signal cloud_state_changed(state: String)
