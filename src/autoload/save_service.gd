extends Node
## SaveService — the single owner of persistent player data (autoload).
##
## Storage model:
##  - Local: JSON at user://save.json — always written, works everywhere.
##  - Cloud: optional CloudSaveAdapter (Firebase Firestore). If signed in
##    and a cloud save exists, CLOUD ALWAYS WINS over local (no merging).
##
## Access model: dotted-path getters/setters over one Dictionary, e.g.
##   SaveService.get_value("economy.blobs", 0)
##   SaveService.set_value("progress.highest_level_unlocked", 4)
## Writes mark the data dirty; a debounced autosave flushes to disk. Systems
## with domain logic (EconomyService, fusion, cards) wrap these calls — UI
## should go through those services, not raw paths.
##
## IN-RUN STATE IS NEVER PERSISTED — only permanent progress lives here.

const SAVE_PATH := "user://save.json"
const SCHEMA_VERSION := 2
## Seconds of quiet after a set_value() before the debounced flush.
const AUTOSAVE_DEBOUNCE_SEC := 1.5

var data: Dictionary = {}

var _dirty := false
var _debounce_timer: SceneTreeTimer = null
var _cloud: CloudSaveAdapter = CloudSaveAdapter.new()


func _ready() -> void:
	load_game()


func _notification(what: int) -> void:
	# Flush on app close / mobile background (data-loss guard).
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _dirty:
			save_now()


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

static func default_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"created_at": int(Time.get_unix_time_from_system()),
		"updated_at": 0,
		"progress": {
			"highest_level_unlocked": 1,
		},
		"economy": {
			"blobs": 0,   # soft currency (Blobs/Shawarmas)
			"tokens": 0,  # hard currency (AL67X Tokens)
			"watts": 0,  # time currency (accrues via WattsService)
			"watts_synced_hours": 0.0,  # last watts accrual sync (unix hours)
			"gems": 0,   # premium currency (Gems — no source yet, top bar ready)
			"loot_boxes": {},  # box_id -> unopened count (opened in Phase 8)
		},
		"allans": {
			"owned": ["player1"],   # ids from data/allans/allans.json
			"equipped": "player1",
		},
		"cards": {
			# owned: card_id -> {"count": int, "upgrades": {"damage": 0, "range": 0, "projectiles": 0, "scale": 0}}
			"owned": {},
			# equipped: up to 6 card ids (the run loadout stack)
			"equipped": [],
		},
		"fusion": {
			"grid": [],              # persisted fusion grid tiles (allan tier ints)
		},
		"amps": {
			"current": 10,
			"max": 10,
			"updated_at": 0,   # unix time of last regen accounting
		},
		"meta": {
			"save_mode": "",            # "" = not chosen | "local" | "cloud"
		},
	}


# ---------------------------------------------------------------------------
# Load / save
# ---------------------------------------------------------------------------

func load_game() -> void:
	data = _read_local()
	if data.is_empty():
		data = default_data()
		_dirty = true
	_migrate()
	# Cloud priority check. On platforms without a backend this is a no-op.
	# The full sign-in flow attaches an adapter via attach_cloud_adapter()
	# (Phase 9); if a cloud save exists it replaces local wholesale.
	EventBus.save_loaded.emit()


## Replace the entire save with defaults (dev/testing + "reset progress").
func reset_to_defaults() -> void:
	data = default_data()
	save_now()
	EventBus.save_loaded.emit()


func save_now() -> void:
	data["updated_at"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot open %s for writing (%s)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	_dirty = false
	EventBus.save_committed.emit()
	if _cloud.is_available() and _cloud.is_signed_in():
		_cloud.push_save(data)


## Swap in a platform cloud backend (Android Firebase in Phase 9; Web later).
## If the cloud has a save, it wins over local immediately.
func attach_cloud_adapter(adapter: CloudSaveAdapter) -> void:
	_cloud = adapter
	if not (_cloud.is_available() and _cloud.is_signed_in()):
		EventBus.cloud_state_changed.emit("signed_out" if _cloud.is_available() else "disabled")
		return
	EventBus.cloud_state_changed.emit("syncing")
	var cloud_data: Variant = await _cloud.fetch_save()
	if cloud_data is Dictionary and not cloud_data.is_empty():
		data = cloud_data
		_migrate()
		save_now()  # mirror cloud → local
		EventBus.save_loaded.emit()
	else:
		# No cloud save yet: first push of the local one.
		await _cloud.push_save(data)
	EventBus.cloud_state_changed.emit("synced")


## Detach the cloud backend (sign-out): saving becomes local-only.
func detach_cloud() -> void:
	_cloud = CloudSaveAdapter.new()
	EventBus.cloud_state_changed.emit("disabled")


# ---------------------------------------------------------------------------
# Dotted-path access
# ---------------------------------------------------------------------------

func get_value(path: String, default: Variant = null) -> Variant:
	var node: Variant = data
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default
	return node


func set_value(path: String, value: Variant) -> void:
	var keys := path.split(".")
	var node: Dictionary = data
	for i in range(keys.size() - 1):
		var key := keys[i]
		if not (node.has(key) and node[key] is Dictionary):
			node[key] = {}
		node = node[key]
	node[keys[keys.size() - 1]] = value
	_mark_dirty()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _read_local() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _migrate() -> void:
	# v1 -> v2: merge-only "fusion energy" became the global Amps pool.
	# Carry any existing player progress across instead of resetting it.
	if int(data.get("schema_version", 1)) < 2:
		var fusion: Dictionary = data.get("fusion", {})
		if fusion.has("energy") or fusion.has("energy_max") or fusion.has("energy_updated_at"):
			var amps: Dictionary = data.get("amps", {})
			if fusion.has("energy"):
				amps["current"] = fusion["energy"]
			if fusion.has("energy_max"):
				amps["max"] = fusion["energy_max"]
			if fusion.has("energy_updated_at"):
				amps["updated_at"] = fusion["energy_updated_at"]
			data["amps"] = amps
			fusion.erase("energy")
			fusion.erase("energy_max")
			fusion.erase("energy_updated_at")
			data["fusion"] = fusion
	# Fill any missing keys from the default schema (forward-compatible when
	# new fields are added in future schema versions).
	_deep_fill(data, default_data())
	data["schema_version"] = SCHEMA_VERSION


func _deep_fill(target: Dictionary, defaults: Dictionary) -> void:
	for key in defaults:
		if not target.has(key):
			target[key] = defaults[key]
		elif target[key] is Dictionary and defaults[key] is Dictionary:
			_deep_fill(target[key], defaults[key])


func _mark_dirty() -> void:
	_dirty = true
	if _debounce_timer != null:
		return
	_debounce_timer = get_tree().create_timer(AUTOSAVE_DEBOUNCE_SEC)
	_debounce_timer.timeout.connect(func() -> void:
		_debounce_timer = null
		if _dirty:
			save_now()
	)
