class_name CurrencyBar
extends HBoxContainer
## One currency readout row for the hub top bar: icon + live balance label.
## The three TopBars scenes (watts / blobs / gems) each instance this script
## with a different `currency` and icon texture. Listens to the matching
## EventBus signal so the label stays live, and refreshes on save load.
## Label shows the bare number (no prefix) — thousands abbreviate to
## "1.2K" style. Gems always show the full number (premium currencies get
## exact counts). Uses the Clash UI font set in the scene.

@export_enum("watts", "blobs", "gems") var currency := "watts"

## Gems show exact counts (never abbreviated). Watts capped at 20 anyway.
@export var abbreviate_thousands := true

const _GETTERS := {
	"watts": "get_watts",
	"blobs": "get_blobs",
	"gems": "get_gems",
}
const _SIGNALS := {
	"watts": "watts_changed",
	"blobs": "blobs_changed",
	"gems": "gems_changed",
}

@onready var _label: Label = $ValueLabel


func _ready() -> void:
	_refresh()
	if currency in _SIGNALS:
		EventBus[_SIGNALS[currency]].connect(_on_balance_changed)
	EventBus.save_loaded.connect(_refresh)


func _on_balance_changed(new_balance: int) -> void:
	_refresh()


func _refresh() -> void:
	var value := 0
	if currency in _GETTERS:
		value = int(EconomyService.call(_GETTERS[currency]))
	_label.text = _format(value)


func _format(value: int) -> String:
	if value < 1000 or not abbreviate_thousands:
		return str(value)
	# 1,234 -> "1.2K"; 12,345 -> "12.3K"; 1,234,567 -> "1.23M"
	if value < 1_000_000:
		var k := value / 1000.0
		if k >= 100.0:
			return "%dK" % int(k)
		return "%.1fK" % k
	var m := value / 1_000_000.0
	if m >= 100.0:
		return "%dM" % int(m)
	return "%.2fM" % m