extends Node
## Full-loop UI flow test (Phase 2/3 gate) — run headless:
##   godot --headless res://scenes/dev/flow_smoke_test.tscn
## Drives the real scenes: hub → Play → REAL generated run level →
## physically collects a shawarma pickup (teleport onto it) → defeats the
## boss via the dev button → verifies banking + level unlock back at hub.
## Exits 0 on PASS, 1 on FAIL. NOTE: resets the local save file.

const STEP_TIMEOUT_FRAMES := 600  # 10s at 60fps per step

var _failures: PackedStringArray = []


func _ready() -> void:
	# This node must survive SceneManager scene swaps: hand the "current
	# scene" role to a disposable placeholder; we stay a plain root child.
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var placeholder := Node.new()
	placeholder.name = "TestPlaceholderScene"
	get_tree().root.add_child(placeholder)
	get_tree().set_current_scene(placeholder)
	_run()


func _run() -> void:
	await _flow()
	if _failures.is_empty():
		print("FLOW TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("FLOW TEST: FAILED (%d)" % _failures.size())
	SaveService.reset_to_defaults()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _flow() -> void:
	var tree := get_tree()
	SaveService.reset_to_defaults()

	# Give SceneManager its first _process, then go to the hub.
	await tree.create_timer(0.5).timeout
	SceneManager.change_scene("res://scenes/hub/hub.tscn", {"speed": 4.0, "wait_time": 0.05})
	if not await _wait_for_scene(tree, "Hub"):
		return

	# "Press PLAY" on the hub — the Home Dashboard's Ignition button now
	# lives in HTML (web_ui/hub/home), which can't render under --headless;
	# drive the exact same ipc_message path hub.gd listens to instead.
	var hub_web := tree.current_scene.get_node_or_null("WebViewHost")
	if hub_web == null:
		_failures.append("hub WebViewHost not found")
		return
	await _wait_transition_settled(tree)
	hub_web.ipc_message.emit(JSON.stringify({"type": "start_run"}))
	if not await _wait_for_scene(tree, "Run"):
		return

	# In the real generated run: physically collect a shawarma by moving
	# the player onto one, then defeat the boss via the dev HUD action.
	var run := tree.current_scene
	var player: Node3D = run.get_node_or_null("Player")
	var pickups: Node = run.get_node_or_null("Pickups")
	if player == null or pickups == null:
		_failures.append("run scene missing Player/Pickups nodes")
		return
	var positions: PackedVector3Array = pickups.get_active_shawarma_positions()
	if positions.is_empty():
		_failures.append("no shawarma pickups spawned in run")
		return
	player.global_position = positions[0]
	var collected := false
	for i in range(STEP_TIMEOUT_FRAMES):
		if int(run._run_blobs) > 0:
			collected = true
			break
		await tree.physics_frame
	if not collected:
		_failures.append("shawarma pickup was not collected on contact")
		return

	await _wait_transition_settled(tree)
	# Dev "Win" button also moved to HTML (web_ui/hud) — same treatment.
	var run_web := run.get_node_or_null("HUD/WebViewHost")
	if run_web == null:
		_failures.append("run WebViewHost not found")
		return
	run_web.ipc_message.emit(JSON.stringify({"type": "dev_boss_win"}))
	if not await _wait_for_scene(tree, "Hub"):
		return

	# Back at the hub: collected blobs banked, level 2 unlocked.
	if EconomyService.get_blobs() < 1:
		_failures.append("expected banked blobs >= 1, got %d" % EconomyService.get_blobs())
	var level := int(SaveService.get_value("progress.highest_level_unlocked", 1))
	if level != 2:
		_failures.append("expected level 2 unlocked, got %d" % level)

	# The bridge's own state contract reflects the banked balance (this is
	# what the HTML top bar actually renders from — see web_ui/hub/home).
	var state := UIBridge.simulate_message_with_reply(JSON.stringify({"type": "request_state"}))
	if int(state.get("blobs", 0)) != EconomyService.get_blobs():
		_failures.append("UIBridge state_sync blobs did not match EconomyService (got: %s)" % state.get("blobs", "<missing>"))


func _wait_for_scene(tree: SceneTree, scene_name: String) -> bool:
	for i in range(STEP_TIMEOUT_FRAMES):
		if tree.current_scene != null and tree.current_scene.name == scene_name and not SceneManager.is_transitioning:
			await tree.process_frame
			return true
		await tree.process_frame
	_failures.append("timed out waiting for scene: %s" % scene_name)
	return false


func _wait_transition_settled(tree: SceneTree) -> void:
	for i in range(STEP_TIMEOUT_FRAMES):
		if not SceneManager.is_transitioning:
			return
		await tree.process_frame
