class_name AllanSprites
extends RefCounted
## Shared, data-driven Allan skin sprite pipeline (spec Section 6).
## Every skin sheet uses the SAME fixed 8x2 grid + frame map defined once in
## data/allans/allans.json — adding skin N+1 is a file drop + registry entry,
## never a per-skin setup. Verified layout: cells 0-4 idle/walk, 5-6 eat,
## 7 succ, 8 cry, 9 front-facing turn frame, 10-15 blank.

static var _registry: Dictionary = {}
static var _thumb_cache: Dictionary = {}


static func registry() -> Dictionary:
	if _registry.is_empty():
		var parsed: Variant = JsonData.load_json("res://data/allans/allans.json")
		_registry = parsed if parsed is Dictionary else {}
	return _registry


static func entry(allan_id: String) -> Dictionary:
	for allan in registry().get("allans", []):
		if str(allan.get("id", "")) == allan_id:
			return allan
	push_error("AllanSprites: unknown allan id '%s'" % allan_id)
	return {}


static func sheet_texture(allan_id: String) -> Texture2D:
	var allan := entry(allan_id)
	if allan.is_empty() or not ResourceLoader.exists(str(allan.get("sheet", ""))):
		return null
	return load(str(allan["sheet"]))


## Pixel-space Rect2 for a frame index in the shared grid.
static func frame_rect(frame_index: int) -> Rect2:
	var layout: Dictionary = registry().get("sheet_layout", {})
	var fw := float(layout.get("frame_width", 879))
	var fh := float(layout.get("frame_height", 1185))
	var columns := int(layout.get("columns", 8))
	var col := frame_index % columns
	var row := frame_index / columns
	return Rect2(col * fw, row * fh, fw, fh)


## state name -> Array[Rect2] (pixel regions), from the shared frame map.
static func state_regions() -> Dictionary:
	var layout: Dictionary = registry().get("sheet_layout", {})
	var frame_map: Dictionary = layout.get("frame_map", {})
	var out: Dictionary = {}
	for state in frame_map:
		var rects: Array = []
		for index in frame_map[state]:
			rects.append(frame_rect(int(index)))
		out[state] = rects
	return out


## Normalized atlas UV rect (offset.xy, scale.zw) for the billboard shader.
static func frame_uv_rect(allan_id: String, frame_index: int) -> Vector4:
	var texture := sheet_texture(allan_id)
	if texture == null:
		return Vector4(0, 0, 1, 1)
	var size := Vector2(texture.get_width(), texture.get_height())
	var rect := frame_rect(frame_index)
	return Vector4(rect.position.x / size.x, rect.position.y / size.y, rect.size.x / size.x, rect.size.y / size.y)


## Frame aspect ratio (width / height) for sizing billboard quads.
static func frame_aspect() -> float:
	var layout: Dictionary = registry().get("sheet_layout", {})
	return float(layout.get("frame_width", 879)) / float(layout.get("frame_height", 1185))


## Small cached thumbnail of a tier's idle frame (fusion grid tiles etc.)
## without keeping the full 7032x2370 sheets resident in VRAM.
static func tier_thumbnail(tier: int, height := 130) -> Texture2D:
	if _thumb_cache.has(tier):
		return _thumb_cache[tier]
	var entry_for_tier: Dictionary = {}
	for allan in registry().get("allans", []):
		if int(allan.get("tier", 0)) == tier:
			entry_for_tier = allan
			break
	var texture: Texture2D = null
	if not entry_for_tier.is_empty():
		texture = sheet_texture(str(entry_for_tier.get("id", "")))
	if texture == null:
		# Placeholder: flat tier-colored square.
		var placeholder := Image.create(96, height, false, Image.FORMAT_RGBA8)
		placeholder.fill(Color.from_hsv(fmod(0.52 + float(tier) * 0.09, 1.0), 0.5, 0.9))
		_thumb_cache[tier] = ImageTexture.create_from_image(placeholder)
		return _thumb_cache[tier]
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	var rect := frame_rect(0)
	var frame := image.get_region(Rect2i(int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)))
	var width := int(float(height) * frame_aspect())
	frame.resize(width, height, Image.INTERPOLATE_LANCZOS)
	_thumb_cache[tier] = ImageTexture.create_from_image(frame)
	return _thumb_cache[tier]
