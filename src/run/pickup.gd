class_name RunPickup
extends Area3D
## A collectible on the run map. Built in code by PickupManager. On player
## contact it emits the contract signal for its type and frees itself —
## downstream systems (run counters, swarm, card/loot systems, audio) react
## via EventBus, never via direct references.

enum Type { SHAWARMA, POWERUP, LOOT_BOX }

var type: int = Type.SHAWARMA
var payload := ""  # powerup id / loot box id
var amount := 1

signal collected(pickup: RunPickup)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player body layer
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(_body: Node3D) -> void:
	match type:
		Type.SHAWARMA:
			EventBus.blob_collected.emit(amount)
		Type.POWERUP:
			EventBus.powerup_picked_up.emit(payload)
		Type.LOOT_BOX:
			EventBus.loot_box_collected.emit(payload)
	collected.emit(self)
	queue_free()
