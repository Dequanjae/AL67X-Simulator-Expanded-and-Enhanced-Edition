class_name CloudSaveAdapter
extends RefCounted
## Base interface for cloud save backends. SaveService talks ONLY to this
## interface — platform specifics live in subclasses:
##   - Android: wraps the GodotFirebaseAndroid plugin (Auth + Firestore).
##   - Desktop/editor: this base class (unavailable, local-save only).
##
## Contract: if the user is signed in and a cloud document exists, CLOUD
## ALWAYS WINS over local (no merge logic — explicitly out of scope).


## Whether a cloud backend exists on this platform at all.
func is_available() -> bool:
	return false


## Whether a user is currently signed in.
func is_signed_in() -> bool:
	return false


## Interactive Google sign-in. Resolves when auth completes/fails/times
## out. Returns success. (async)
func sign_in_interactive() -> bool:
	return false


## Fetch the cloud save document. Returns a Dictionary, or null if none
## exists / not signed in / error. (async)
func fetch_save() -> Variant:
	return null


## Push the full save data to the cloud document. Returns success. (async)
func push_save(_data: Dictionary) -> bool:
	return false
