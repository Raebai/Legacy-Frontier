extends Node
## Suppress a boss's TOP-BAR PRESENCE. Not a modifier — a rider that says "this one
## is a boss body, but it is not The Boss of this floor."
##
## Attached by `Encounter.build_enemy_from_data` whenever a spawn dictionary carries
## `quiet: true`. Today the only thing that sets it is a SPLIT copy, but the shape
## is general: any future "there are two of them" mechanic needs the same thing.
##
## ── WHY IT IS A NODE AND NOT A FLAG ON THE BOSS ──────────────────────────────
## The bar and the intro card are built inside `Boss._ready()`, which cannot be
## edited and which reads nothing that a spawn dictionary can set (only
## `body_scale` is exposed pre-`_ready`). So the honest options are "edit Boss.gd"
## or "let it build them and take them away on the next frame". The second one
## needs no edit and, because it runs on every peer from replicated data, it also
## behaves identically in co-op — which the first one would not, since the co-op
## add_child lives in Arena.gd.
##
## The bar is FREED rather than hidden: it polls the boss's hp every frame for the
## whole fight and there is no reason to pay for a bar nobody will see.

## Phase to snap the body into, skipping the boss's 2.6 s intro. A split copy has to
## arrive already fighting — its parent just exploded, the drama is spent, and a
## pair of statues standing still for two and a half seconds reads as a spawn bug.
var target_phase: int = 1

var _done: bool = false


func _process(_delta: float) -> void:
	if _done:
		set_process(false)
		return
	_done = true
	var boss: Node = get_parent()
	if boss == null or not is_instance_valid(boss):
		return
	var layer: Variant = boss.get("_bar_layer")
	if layer is Node and is_instance_valid(layer):
		# Takes the intro card with it: `Boss._play_intro` parents the card to this
		# same layer, so one free() removes both.
		(layer as Node).queue_free()
		boss.set("_bar_layer", null)
		boss.set("_bar", null)
	if boss.has_method("_enter_phase") and int(boss.call("current_phase")) == 0:
		boss.call("_enter_phase", clampi(target_phase, 1, 3))
	set_process(false)
