class_name CurrencyBar
extends HBoxContainer
## One currency readout row for the hub top bar: icon + live balance label.
## Reusable — the three TopBars scenes (watts / blobs / gems) each instance
## this script with a different `currency` and icon texture. Listens to the
## matching EventBus signal so the label stays live, and refreshes on save
## load. Editable per-currency scenes live in scenes/ui/TopBars/.

@export_enum("watts", "blobs", "gems") var currency := "watts"

## Label text prefix, e.g. "Watts:" — set per scene.
@export var prefix := "Watts:"

## Format: "%s 1,234". Set true for the big counters, false for plain ints.
@export var use_thousands_separator := false

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
	_label.text = "%s %s" % [prefix, _format(value)]


func _format(value: int) -> String:
	if use_thousands_separator:
		var s := str(value)
		var out := ""
		var count := 0
		for i in range(s.length() - 1, -1, -1):
			out = s[i] + out
			count += 1
			if count % 3 == 0 and i > 0:
				out = "," + out
		return out
	return str(value)