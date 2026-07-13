class_name CloudSaveAndroid
extends CloudSaveAdapter
## Android cloud save backend: GodotFirebaseAndroid plugin (Firebase Auth
## Google sign-in + Firestore). The whole save is stored as one JSON string
## field in saves/{uid} — robust against plugin type-conversion quirks and
## schema-agnostic.
##
## ⚠️ DEVICE-VERIFY REQUIRED: sign-in will FAIL until the debug keystore
## SHA-1 is registered in the Firebase console (google-services.json
## currently has an empty oauth_client — see docs/ARCHITECTURE.md SWAP
## POINTS). The Firestore result-dictionary shapes below are parsed
## defensively and should be confirmed on first device test.

const COLLECTION := "saves"
const AUTH_TIMEOUT_SEC := 90.0
const FIRESTORE_TIMEOUT_SEC := 20.0


func is_available() -> bool:
	return Engine.has_singleton("GodotFirebaseAndroid")


func is_signed_in() -> bool:
	return is_available() and Firebase.auth.is_signed_in()


func sign_in_interactive() -> bool:
	if not is_available():
		return false
	if is_signed_in():
		return true
	var auth: Node = Firebase.auth
	var state := [false, false]  # [completed, success]
	var on_success := func(_user: Dictionary) -> void:
		state[0] = true
		state[1] = true
	var on_failure := func(_error: String) -> void:
		state[0] = true
	auth.auth_success.connect(on_success, CONNECT_ONE_SHOT)
	auth.auth_failure.connect(on_failure, CONNECT_ONE_SHOT)
	auth.sign_in_with_google()
	var ok := await _poll(state, AUTH_TIMEOUT_SEC)
	if auth.auth_success.is_connected(on_success):
		auth.auth_success.disconnect(on_success)
	if auth.auth_failure.is_connected(on_failure):
		auth.auth_failure.disconnect(on_failure)
	return ok


func fetch_save() -> Variant:
	if not is_signed_in():
		return null
	var uid := _uid()
	if uid == "":
		return null
	var firestore: Node = Firebase.firestore
	var holder := [false, {}]  # [completed, result]
	var on_result := func(result: Dictionary) -> void:
		holder[0] = true
		holder[1] = result
	firestore.get_task_completed.connect(on_result, CONNECT_ONE_SHOT)
	firestore.get_document(COLLECTION, uid)
	var completed := await _poll(holder, FIRESTORE_TIMEOUT_SEC, true)
	if firestore.get_task_completed.is_connected(on_result):
		firestore.get_task_completed.disconnect(on_result)
	if not completed:
		return null
	var doc := _extract_document(holder[1])
	if doc.has("save_json"):
		var parsed: Variant = JSON.parse_string(str(doc["save_json"]))
		return parsed if parsed is Dictionary else null
	return null


func push_save(data: Dictionary) -> bool:
	if not is_signed_in():
		return false
	var uid := _uid()
	if uid == "":
		return false
	var firestore: Node = Firebase.firestore
	var holder := [false, {}]
	var on_result := func(result: Dictionary) -> void:
		holder[0] = true
		holder[1] = result
	firestore.write_task_completed.connect(on_result, CONNECT_ONE_SHOT)
	firestore.set_document(COLLECTION, uid, {
		"save_json": JSON.stringify(data),
		"updated_at": int(Time.get_unix_time_from_system()),
	})
	var completed := await _poll(holder, FIRESTORE_TIMEOUT_SEC, true)
	if firestore.write_task_completed.is_connected(on_result):
		firestore.write_task_completed.disconnect(on_result)
	return completed and not _is_error(holder[1])


# ---------------------------------------------------------------------------

func _uid() -> String:
	var user: Dictionary = Firebase.auth.get_current_user_data()
	for key in ["uid", "userId", "user_id", "localId", "id"]:
		if user.has(key) and str(user[key]) != "":
			return str(user[key])
	return ""


## Defensive parse of the plugin's get_task_completed payload: accepts the
## document under a "data" key, or fields at the top level.
func _extract_document(result: Dictionary) -> Dictionary:
	if _is_error(result):
		return {}
	if result.get("data") is Dictionary:
		return result["data"]
	if result.get("document") is Dictionary:
		return result["document"]
	return result


func _is_error(result: Dictionary) -> bool:
	if result.has("error") and result["error"]:
		return true
	if result.has("success") and not bool(result["success"]):
		return true
	if str(result.get("status", "")).to_lower() in ["error", "failure", "failed"]:
		return true
	return false


## state[0] flips true on completion. Returns state[1] (or completion for
## `return_completed`).
func _poll(state: Array, timeout_sec: float, return_completed := false) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var waited := 0.0
	while not state[0] and waited < timeout_sec:
		await tree.process_frame
		waited += 1.0 / 60.0
	if return_completed:
		return bool(state[0])
	return bool(state[1])
