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
##
## One cell is always a whole tank, asked for as the player's own maximum rather
## than carried here as a number that happens to match it. Retuning the torch's
## capacity must never quietly turn a battery into a partial refill.


func _on_interacted(player: Node) -> void:
	if not player.has_method(&"add_flashlight_battery"):
		return
	var full := float(player.get(&"flashlight_battery_max"))
	if float(player.call(&"add_flashlight_battery", full)) <= 0.0:
		return
	# Consumed on the authority only, which is also the only side that runs
	# _try_interact(): the replicator turns this into a despawn every client
	# hears, the way any other item leaving the world is.
	queue_free()
