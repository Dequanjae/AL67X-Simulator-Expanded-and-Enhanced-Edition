extends Node
## One-off probe: boot → PLAY NOW → hub, with per-frame tracing. Headless:
##   godot --headless res://scenes/dev/boot_hub_probe.tscn

const STEP_TIMEOUT_FRAMES := 1200


func _ready() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var placeholder := Node.new()
	placeholder.name = "TestPlaceholderScene"
	get_tree().root.add_child(placeholder)
	get_tree().set_current_scene(placeholder)
	SaveService._cloud = CloudSaveAdapter.new()
	SaveService.reset_to_defaults()
	await get_tree().create_timer(0.5).timeout
	print("PROBE: change_scene(boot)")
	SceneManager.change_scene("res://scenes/boot/boot.tscn", {"speed": 4.0, "wait_time": 0.05})
	var tree := get_tree()
	var ok := false
	for i in range(STEP_TIMEOUT_FRAMES):
		if tree.current_scene != null and tree.current_scene.name == "Boot" and not SceneManager.is_transitioning:
			ok = true
			break
		await tree.process_frame
	if not ok:
		print("PROBE: boot never appeared, current=%s transitioning=%s" % [str(tree.current_scene.name if tree.current_scene else "null"), SceneManager.is_transitioning])
		_finish(false)
		return
	print("PROBE: Boot up (transitioning=%s)" % SceneManager.is_transitioning)
	var boot := tree.current_scene
	var menu: VBoxContainer = boot.get_node("Menu")
	for i in range(STEP_TIMEOUT_FRAMES):
		if menu.visible:
			break
		await tree.process_frame
	print("PROBE: menu visible (frames waited above), transitioning=%s" % SceneManager.is_transitioning)
	(boot.get_node("Menu/PlayNowButton") as Button).pressed.emit()
	print("PROBE: PlayNow emitted, transitioning=%s" % SceneManager.is_transitioning)
	for i in range(STEP_TIMEOUT_FRAMES):
		if i % 120 == 0:
			print("PROBE: frame %d current=%s transitioning=%s" % [i, str(tree.current_scene.name if tree.current_scene else "null"), SceneManager.is_transitioning])
		if tree.current_scene != null and tree.current_scene.name == "Hub" and not SceneManager.is_transitioning:
			print("PROBE: HUB REACHED ✓")
			_finish(true)
			return
		await tree.process_frame
	print("PROBE: hub never became current")
	_finish(false)


func _finish(ok: bool) -> void:
	SaveService.reset_to_defaults()
	get_tree().quit(0 if ok else 1)