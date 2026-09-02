class_name FlashlightBattery
extends RitualItem

## A spare cell for the torch. It inherits RitualItem for one reason: the
## seen-by-camera highlight, which is the difference between "there is a battery
## in this room" and "there is a battery somewhere in an 80 x 60 m villa with
## the lights out".
##
## Where it parts company with the totems is what interacting does. A battery
## never goes into a hand - "not enough hands" is a cost the objective is
## supposed to charge, not something a consumable should tax - so picking it up
## spends it on the spot and the item leaves the world. A player whose torch is
## already full takes nothing and leaves it where it is, for whoever needs it.

## Charge one cell restores, in the same units as Player.flashlight_battery_max.
## A full one on purpose: a battery is a find, and a find that gives back a
## third of a tank is an errand.
@export_range(1.0, 500.0, 1.0) var charge_amount: float = 100.0


func _on_interacted(player: Node) -> void:
	if not player.has_method(&"add_flashlight_battery"):
		return
	if float(player.call(&"add_flashlight_battery", charge_amount)) <= 0.0:
		return
	# Consumed on the authority only, which is also the only side that runs
	# _try_interact(): the replicator turns this into a despawn every client
	# hears, the way any other item leaving the world is.
	queue_free()
