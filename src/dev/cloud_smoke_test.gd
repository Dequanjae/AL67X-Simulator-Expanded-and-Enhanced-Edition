extends Node
## Cloud save gate (Phase 9) — run headless:
##   godot --headless res://scenes/dev/cloud_smoke_test.tscn
## Uses a MOCK CloudSaveAdapter to verify the platform-independent cloud
## contract end-to-end (the Android Firebase wiring itself needs on-device
## verification — SHA-1 registration pending):
##  - cloud-wins-over-local on attach (no merge),
##  - local file mirrors the cloud data after attach,
##  - first sign-in with no cloud doc pushes the local save up,
##  - every save_now() pushes to the cloud while signed in,
##  - unavailable/signed-out adapters emit the right states and change nothing,
##  - boot UI: fresh save shows both paths; PLAY NOW persists local mode and
##    enters the hub; subsequent boots skip the menu.
## Exits 0 on PASS, 1 on FAIL. NOTE: resets the local save file.

const STEP_TIMEOUT_FRAMES := 1200

var _failures: PackedStringArray = []
var _cloud_states: PackedStringArray = []


class MockCloud extends CloudSaveAdapter:
	var available := true
	var signed_in := true
	var doc: Variant = null
	var pushes: Array = []

	func is_available() -> bool:
		return available

	func is_signed_in() -> bool:
		return signed_in

	func sign_in_interactive() -> bool:
		return signed_in

	func fetch_save() -> Variant:
		return doc

	func push_save(data: Dictionary) -> bool:
		pushes.append(data.duplicate(true))
		return true


func _ready() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var placeholder := Node.new()
	placeholder.name = "TestPlaceholderScene"
	get_tree().root.add_child(placeholder)
	get_tree().set_current_scene(placeholder)
	_run()


func _run() -> void:
	await _test_contract()
	await _test_boot_ui()
	if _failures.is_empty():
		print("CLOUD TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("CLOUD TEST: FAILED (%d)" % _failures.size())
	# Restore a clean default state (and detach the mock adapter).
	SaveService._cloud = CloudSaveAdapter.new()
	SaveService.reset_to_defaults()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures.append(name)


func _test_contract() -> void:
	EventBus.cloud_state_changed.connect(func(state: String) -> void: _cloud_states.append(state))

	# --- 1. Cloud wins over local ----------------------------------------
	SaveService.reset_to_defaults()
	SaveService.set_value("progress.highest_level_unlocked", 2)
	SaveService.save_now()
	var cloud_data := SaveService.default_data()
	cloud_data["progress"]["highest_level_unlocked"] = 7
	cloud_data["economy"]["blobs"] = 555
	var mock := MockCloud.new()
	mock.doc = cloud_data
	await SaveService.attach_cloud_adapter(mock)
	_check(int(SaveService.get_value("progress.highest_level_unlocked", 1)) == 7, "cloud save wins over local")
	_check(EconomyService.get_blobs() == 555, "cloud balances applied")
	_check(_cloud_states.has("syncing") and _cloud_states.has("synced"), "sync states emitted")
	# Local file mirrors the cloud.
	SaveService.data = {}
	SaveService._cloud = CloudSaveAdapter.new()  # avoid re-fetch on reload
	SaveService.load_game()
	_check(int(SaveService.get_value("progress.highest_level_unlocked", 1)) == 7, "local file mirrors cloud after attach")

	# --- 2. No cloud doc → local pushed up --------------------------------
	SaveService.reset_to_defaults()
	SaveService.set_value("progress.highest_level_unlocked", 4)
	var fresh := MockCloud.new()
	fresh.doc = null
	await SaveService.attach_cloud_adapter(fresh)
	_check(fresh.pushes.size() >= 1, "first sign-in pushes local save to cloud")
	if not fresh.pushes.is_empty():
		_check(int(fresh.pushes[0]["progress"]["highest_level_unlocked"]) == 4, "pushed data matches local")

	# --- 3. save_now pushes while signed in --------------------------------
	var push_count := fresh.pushes.size()
	SaveService.set_value("economy.blobs", 42)
	SaveService.save_now()
	_check(fresh.pushes.size() == push_count + 1, "save_now pushes to cloud")
	_check(int(fresh.pushes.back()["economy"]["blobs"]) == 42, "pushed data is current")

	# --- 4. Unavailable / signed-out states --------------------------------
	_cloud_states.clear()
	var disabled := MockCloud.new()
	disabled.available = false
	await SaveService.attach_cloud_adapter(disabled)
	_check(_cloud_states.has("disabled"), "unavailable adapter → disabled state")
	_cloud_states.clear()
	var signed_out := MockCloud.new()
	signed_out.signed_in = false
	var level_before := int(SaveService.get_value("progress.highest_level_unlocked", 1))
	await SaveService.attach_cloud_adapter(signed_out)
	_check(_cloud_states.has("signed_out"), "signed-out adapter → signed_out state")
	_check(int(SaveService.get_value("progress.highest_level_unlocked", 1)) == level_before, "signed-out attach changes nothing")
	_check(signed_out.pushes.is_empty(), "signed-out adapter never pushed")

	# Android adapter is safely inert off-device.
	var android := CloudSaveAndroid.new()
	_check(not android.is_available(), "android adapter unavailable off-device")
	_check(not await android.sign_in_interactive(), "android sign-in inert off-device")


func _test_boot_ui() -> void:
	var tree := get_tree()

	# Fresh save → boot shows both save paths.
	SaveService._cloud = CloudSaveAdapter.new()
	SaveService.reset_to_defaults()
	await tree.create_timer(0.5).timeout
	SceneManager.change_scene("res://scenes/boot/boot.tscn", {"speed": 4.0, "wait_time": 0.05})
	if not await _wait(func() -> bool: return tree.current_scene != null and tree.current_scene.name == "Boot" and not SceneManager.is_transitioning, "boot loads"):
		return
	var boot := tree.current_scene
	var menu: VBoxContainer = boot.get_node("Menu")
	if not await _wait(func() -> bool: return menu.visible, "fresh save shows save-path menu"):
		return
	var google_button: Button = boot.get_node("Menu/GoogleButton")
	_check(google_button.disabled, "google button disabled off-android")

	# PLAY NOW persists local mode and enters the hub.
	(boot.get_node("Menu/PlayNowButton") as Button).pressed.emit()
	if not await _wait(func() -> bool: return tree.current_scene != null and tree.current_scene.name == "Hub" and not SceneManager.is_transitioning, "play now enters hub"):
		return
	_check(str(SaveService.get_value("meta.save_mode", "")) == "local", "local mode persisted")

	# Subsequent boot skips the menu entirely.
	SceneManager.change_scene("res://scenes/boot/boot.tscn", {"speed": 4.0, "wait_time": 0.05})
	if not await _wait(func() -> bool: return tree.current_scene != null and tree.current_scene.name == "Hub" and not SceneManager.is_transitioning, "local mode boots straight to hub"):
		return


func _wait(predicate: Callable, name: String) -> bool:
	for i in range(STEP_TIMEOUT_FRAMES):
		if predicate.call():
			return true
		await get_tree().process_frame
	_failures.append("timed out: %s" % name)
	return false
