class_name WattsBar
extends VBoxContainer
## Watts top bar element — bare count (Clash-Bold, capped at 20, full
## number) over a YELLOW generation progress bar that fills over one
## watt's accrual time (15s at per_hour=240); each completed cycle banks
## +1 watt via WattsService (fraction preserved) and the bar restarts.
## Countdown readout at the bottom; "FULL" at the cap. Progress comes
## from WattsService.watts_progress() — real accrual math, survives app
## restarts and offline time.

var _cap := 20
var _per_watt_seconds := 15.0

@onready var _count_label: Label = $Top/WattsLabel
@onready var _fill_bar: ProgressBar = $FillBar
@onready var _timer_label: Label = $TimerLabel


func _ready() -> void:
	var cfg := WattsService.config()
	_cap = int(cfg.get("cap", 20))
	_per_watt_seconds = 3600.0 / maxf(1.0, float(cfg.get("per_hour", 240)))
	_fill_bar.min_value = 0.0
	_fill_bar.max_value = 100.0
	_fill_bar.show_percentage = false
	# Seed the accrual clock if this is the first ever read; after this the
	# per-frame path is read-only except when banking completed cycles.
	EconomyService.get_watts()
	_refresh_count()
	EventBus.watts_changed.connect(func(_v: int) -> void: _refresh_count())
	EventBus.save_loaded.connect(func() -> void: _refresh_count())


func _process(_delta: float) -> void:
	var p: Dictionary = WattsService.watts_progress()
	# Bank any completed cycles — get_watts() is the banking operation
	# (sync math advances the full watts, PRESERVES the fraction).
	if int(p.get("cycles", 0)) > 0:
		EconomyService.get_watts()
		_refresh_count()
		p = WattsService.watts_progress()
	if p.get("full", false) or EconomyService.get_watts_readonly() >= _cap:
		_fill_bar.value = 100.0
		_timer_label.text = "FULL"
		return
	var fraction := float(p.get("fraction", 0.0))
	_fill_bar.value = fraction * 100.0
	_timer_label.text = "%.1fs" % maxf(0.0, (1.0 - fraction) * _per_watt_seconds)


func _refresh_count() -> void:
	_count_label.text = str(EconomyService.get_watts_readonly())