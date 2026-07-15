class_name IconFactory
extends RefCounted

static var _cache: Dictionary = {}


static func heart(filled := true) -> Texture2D:
	var key := "heart_%s" % filled
	if _cache.has(key):
		return _cache[key]
	var size := 40
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var color := Color(1.0, 0.25, 0.3) if filled else Color(0.35, 0.35, 0.4, 0.8)
	for py in range(size):
		for px in range(size):
			var x := (float(px) / size - 0.5) * 2.6
			var y := (0.5 - float(py) / size) * 2.6 + 0.25
			var a := x * x + y * y - 1.0
			if a * a * a - x * x * y * y * y <= 0.0:
				image.set_pixel(px, py, color)
	_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


static func shield() -> Texture2D:
	if _cache.has("shield"):
		return _cache["shield"]
	var size := 40
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var color := Color(0.35, 0.85, 1.0)
	for py in range(size):
		for px in range(size):
			var x := absf(float(px) / size - 0.5) * 2.0
			var y := float(py) / size
			var half_width := 0.9 - 0.75 * maxf(0.0, y - 0.35) / 0.65
			if y > 0.05 and y < 0.98 and x < half_width:
				image.set_pixel(px, py, color)
	_cache["shield"] = ImageTexture.create_from_image(image)
	return _cache["shield"]
