# Throwaway headless check: BLINK_STRIKE now dispatches through SpellCaster (it
# used to be hand-rolled in Hero, so it was dead everywhere else). Confirms the arm
# spawns a spectacle AND that a caster exposing blink_to() is moved to the vetted
# landing spot the callback returns.
#   Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/blink_dispatch_check.gd
extends SceneTree


class FakeCaster:
	extends Node2D
	var moved_to: Vector2 = Vector2.ZERO
	var was_called: bool = false

	## Mimics Hero.blink_to: veto part of the requested distance, then report back
	## where we ACTUALLY landed (proving the dispatcher honours the return value).
	func blink_to(dest: Vector2) -> Vector2:
		was_called = true
		moved_to = dest * 0.5
		global_position = moved_to
		return moved_to


func _initialize() -> void:
	_run()


## Async: nothing is actually inside the tree during _initialize(), and
## SpellCaster.cast() (correctly) refuses to parent a spectacle to a detached
## arena — so wait a frame before casting or every arm reports a false failure.
func _run() -> void:
	var failed: int = 0
	var arena := Node2D.new()
	root.add_child(arena)
	await process_frame

	var spell := SpellDef.new()
	spell.id = "blink_strike"
	spell.kind = SpellDef.Kind.BLINK_STRIKE
	spell.reach = 200.0
	spell.damage = 50
	spell.effect = "shadow"

	# 1) With no caster at all, the arm must still spawn the cut (no crash).
	var ok: bool = SpellCaster.cast(spell, arena, Vector2.ZERO, Vector2(300, 0), Color.WHITE, "shadow")
	failed += _expect(ok, "BLINK_STRIKE dispatches through SpellCaster")
	failed += _expect(_has_blink_cut(arena), "the blink cut spectacle is spawned")

	# 2) With a caster, blink_to is called and its returned position is authoritative.
	var fc := FakeCaster.new()
	arena.add_child(fc)
	SpellCaster.cast(spell, arena, Vector2.ZERO, Vector2(300, 0), Color.WHITE, "shadow", fc)
	failed += _expect(fc.was_called, "the caster's blink_to() callback is invoked")
	failed += _expect(fc.global_position == fc.moved_to,
		"the caster ends up where blink_to() said, not where the spell asked")

	# 3) Reach clamps the requested destination before the callback sees it.
	var far := FakeCaster.new()
	arena.add_child(far)
	SpellCaster.cast(spell, arena, Vector2.ZERO, Vector2(5000, 0), Color.WHITE, "shadow", far)
	failed += _expect(far.moved_to.length() <= spell.reach,
		"a target beyond reach is clamped to reach before blinking")

	print("blink dispatch check: ", "all PASS" if failed == 0 else "%d FAILED" % failed)
	quit(1 if failed > 0 else 0)


## The cut is identified by its script PATH, not by child count (the cast also
## spawns VFX children, so counting is fragile) and not by `is BlinkStrike` —
## naming the class here would early-compile BlinkStrike.gd and its `Sfx` autoload
## reference, which does not exist under a bare `--script` run. Same reason
## SpellCaster load()s every spectacle by path.
func _has_blink_cut(arena: Node) -> bool:
	for c: Node in arena.get_children():
		var s: Script = c.get_script() as Script
		if s != null and s.resource_path == SpellCaster.BLINK_PATH:
			return true
	return false


func _expect(cond: bool, what: String) -> int:
	if not cond:
		printerr("  FAIL: ", what)
		return 1
	return 0
