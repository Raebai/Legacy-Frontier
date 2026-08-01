extends EliteRider
## VOLATILE — "the ink never dried."
##
## It bursts when it dies. Not immediately at full strength and not without warning:
## below `FIZZ_FRACTION` it starts pulsing, faster the closer it gets to zero, and the
## pulse IS the telegraph. Kill it somewhere else.
##
## ── WHAT IT CHANGES ABOUT THE FIGHT ──────────────────────────────────────────
## Where you finish things. Nothing in this game currently makes a kill a decision —
## you burst the nearest body because there is never a reason not to. A volatile one
## puts a cost on the last hit and, more interestingly, on the last hit's POSITION:
## the honest play is to back off and finish it at range, or to let it walk into the
## crowd first. That is an interaction, not a stat.
##
## ── WHY THE HOOK IS `tree_exiting` AND NOT A POLL ────────────────────────────
## `Enemy` has no death signal. `_die()` runs synchronously inside `take_damage` and
## ends in `queue_free()`, so a rider polling `hp <= 0` in `_process` races the frame
## and misses roughly half of them depending on node order. `tree_exiting` fires once,
## deterministically, on the way out — and the `hp > 0` guard below is what separates
## "it was killed" from "the whole arena was torn down", which must NOT detonate.
##
## The blast is parented to the ARENA, which is not the node being removed, so it
## outlives the corpse exactly the way the death burst and the corpse silhouette
## already do.

const BLAST_SCENE: String = "res://scenes/combat/BlastSpell.tscn"

## Sized against BOMBER (30 damage / 78px), and deliberately UNDER it: the bomber's
## blast is an attack you are given a fuse to escape, this one is a consequence you
## chose the timing of. Being punished for a kill you earned should sting, not delete.
const DAMAGE: int = 18
const RADIUS: float = 74.0
const KNOCKBACK: float = 280.0

## HP fraction below which the fizz starts. The player needs a beat of warning BEFORE
## the last hit, not on it.
const FIZZ_FRACTION: float = 0.55
const FIZZ_SLOW: float = 0.70   # seconds between pulses at the top of the band
const FIZZ_FAST: float = 0.16   # ...and at the bottom

var _fizz: float = 0.0
var _armed: bool = false


func _setup() -> void:
	if enemy.has_signal("tree_exiting") and not enemy.is_connected("tree_exiting", _on_gone):
		enemy.connect("tree_exiting", _on_gone)
	_armed = true


## Runs on EVERY peer: a client that cannot see the fizz cannot know to back off, and
## the blast's damage twin arrives over `Net.broadcast_blast` from the host.
func _tick_visual(delta: float) -> void:
	var mx: int = int(enemy.get("max_hp"))
	if mx <= 0:
		return
	var frac: float = clampf(float(enemy.get("hp")) / float(mx), 0.0, 1.0)
	if frac > FIZZ_FRACTION:
		return
	_fizz -= delta
	if _fizz > 0.0:
		return
	# Closer to death = faster pulse. The rate is the countdown.
	_fizz = lerpf(FIZZ_FAST, FIZZ_SLOW, frac / FIZZ_FRACTION)
	var r: Node = rig()
	if r == null or not is_instance_valid(r):
		return
	var c: Color = tint()
	# HDR (> 1) so it blooms, the same treatment an elemental tick already gets.
	r.call("flash_color", Color(c.r * 1.6 + 0.2, c.g * 1.6 + 0.2, c.b * 1.6 + 0.2), 0.1)


## THE BURST. Host-only, and only on a real death.
func _on_gone() -> void:
	if not _armed or not is_authority():
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	# ⚠ THE GUARD IS THE WHOLE FUNCTION. `tree_exiting` also fires when the floor is
	# torn down between waves, when the run ends, and on every headless teardown. A
	# body leaving the tree with hp still on it was NOT killed, and detonating there
	# would drop a live blast into a dying scene.
	if int(enemy.get("hp")) > 0:
		return
	var host: Node = arena()
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	var at: Vector2 = enemy_pos()
	var scene: PackedScene = load(BLAST_SCENE) as PackedScene
	if scene == null:
		return
	var blast: Node2D = scene.instantiate() as Node2D
	# Ownership + configuration BEFORE it goes anywhere. An un-owned spectacle is
	# inert in the whole reaction system and nothing errors about it (see
	# EliteRider.stamp_hostile).
	stamp_hostile(blast, Elements.Element.FIRE, SpellTier.Tier.QUICK)
	blast.call("configure", {
		"target_group": "hero",
		"damage": DAMAGE,
		"radius": RADIUS,
		"knockback": KNOCKBACK,
		"element_id": Elements.Element.FIRE,
	})
	# ⚠ BOTH OF THESE ARE DEFERRED, AND THE FIRST CUT OF THIS WAS NOT.
	# `tree_exiting` fires while the SceneTree is mid-removal, and a direct
	# `host.add_child(blast)` there fails outright — "Parent node is busy setting up
	# children" — leaving an unparented blast that then errors its way through
	# `detonate_now` (no tree, so no group scan, no timer, no damage). It looked like
	# a working affix that simply never hurt anyone.
	#
	# Deferred calls flush in submission order at idle, after the removal has
	# completed, so the add lands first and the detonation second. Both callables
	# target `blast` and `host` — never this rider, which is being freed alongside the
	# corpse and whose deferred calls would simply be dropped.
	host.add_child.call_deferred(blast)
	blast.call_deferred("detonate_now", at)
	if _net != null and _net.is_active():
		_net.broadcast_blast(at, Elements.Element.FIRE, RADIUS)
