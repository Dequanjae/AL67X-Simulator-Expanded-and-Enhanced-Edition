extends SceneTree
## One-off: generate a gem currency icon (assets/UI/Currency/Gem.png).
## Godot image API so the .import sidecar is produced by the editor rescan.

func _init() -> void:
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	# Diamond: top table, pavilion below — cyan-green gem.
	var light := Color(0.45, 0.95, 0.85)
	var mid := Color(0.20, 0.75, 0.65)
	var dark := Color(0.10, 0.45, 0.45)
	var edge := Color(0.85, 1.0, 0.95)
	for py in range(size):
		for px in range(size):
			var x := float(px) / size
			var y := float(py) / size
			# Crown: wide trapezoid from y=0.18 (full width) to y=0.45 (mid width)
			# Pavilion: triangle 0.45 -> 1.0 narrowing to the tip.
			var c := Color(0, 0, 0, 0)
			var half_w := 0.0
			if y >= 0.18 and y < 0.45:
				half_w = 0.5 - (y - 0.18) * (0.30 / 0.27)
				if x > 0.5 - half_w and x < 0.5 + half_w:
					c = light.lerp(mid, (y - 0.18) / 0.27)
			elif y >= 0.45 and y <= 1.0:
				half_w = 0.20 * (1.0 - (y - 0.45) / 0.55)
				if x > 0.5 - half_w and x < 0.5 + half_w:
					c = mid.lerp(dark, (y - 0.45) / 0.55)
			# Girdle highlight + facet sparkle
			if c.a > 0:
				if absf(y - 0.45) < 0.03:
					c = edge
				if x > 0.5 - half_w + 0.04 and y < 0.28:
					c = light.lerp(Color.WHITE, 0.5)
			img.set_pixel(px, py, c)
	img.save_png("res://assets/UI/Currency/Gem.png")
	print("GEM ICON WRITTEN")
	quit()