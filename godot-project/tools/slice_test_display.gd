extends SceneTree
## FULLSCREEN IS ACTUALLY WIRED, AND THE HUD IS NOT A SECOND COPY OF ITSELF.
##
## ⚠ THE BUG THIS EXISTS FOR: the `fullscreen` input action was written to the END of
## project.godot, which put it inside `[rendering]` instead of `[input]`. Everything
## looked right — the autoload was there, the handler was there, the keycode was there —
## and `is_action_pressed(&"fullscreen")` could never fire because the action did not
## exist. A source-grep would have passed. This asks the INPUT MAP.

## ⚠ DEFERRED, BECAUSE `_initialize` RUNS BEFORE THE TREE EXISTS. Querying
## `/root/Screen` from there returns null with "Can't use get_node() with absolute
## paths from outside the active scene tree" — and the first version of this suite read
## that as "the autoload is not registered" and reported a wiring bug that was not
## there. Autoloads are only reachable once a frame has passed.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var fails: int = 0

	# 1. The action exists where an action has to exist to be an action.
	if not InputMap.has_action(&"fullscreen"):
		printerr("  FAIL: no `fullscreen` action in the input map — check it is under "
			+ "[input] in project.godot and not appended into another section")
		fails += 1
	else:
		var bound: bool = false
		for e: InputEvent in InputMap.action_get_events(&"fullscreen"):
			if e is InputEventKey:
				bound = true
		if not bound:
			printerr("  FAIL: `fullscreen` has no key bound to it")
			fails += 1

	# 2. The autoload that answers it is on the tree with the API the menu calls.
	var scr: Node = root.get_node_or_null(^"/root/Screen")
	if scr == null:
		printerr("  FAIL: the Screen autoload is not on the tree")
		fails += 1
	else:
		for m: String in ["toggle", "set_fullscreen", "is_fullscreen"]:
			if not scr.has_method(m):
				printerr("  FAIL: Screen is missing `%s`" % m)
				fails += 1

	# 3. ONE owner for the HUD's height. The camera used to keep its own copy of
	#    AbilityBar's arithmetic and it went stale the moment the bar was rescaled.
	var cam_src: FileAccess = FileAccess.open(
		"res://scripts/combat/CombatCamera.gd", FileAccess.READ)
	if cam_src != null:
		var src: String = cam_src.get_as_text()
		cam_src.close()
		if not src.contains("AbilityBar.occupied_height"):
			printerr("  FAIL: CombatCamera is not asking AbilityBar for its height")
			fails += 1

	# 4. The bar yields on desktop. 46 px is a THUMB target; a keyboard has no thumb.
	var k: float = AbilityBar.slot_scale()
	if k > 1.0 or k <= 0.0:
		printerr("  FAIL: slot_scale out of range (%.2f)" % k)
		fails += 1
	if AbilityBar.occupied_height() <= 0.0:
		printerr("  FAIL: occupied_height must be positive")
		fails += 1
	# The locked constant itself must never have been edited to achieve the shrink.
	if not is_equal_approx(AbilityBar.SLOT_SIZE, 46.0):
		printerr("  FAIL: SLOT_SIZE moved off its locked 46 px thumb target (got %.1f)"
			% AbilityBar.SLOT_SIZE)
		fails += 1

	if fails > 0:
		printerr("Display tests: %d FAILED" % fails)
	else:
		print("Display tests: all PASS")
	quit(1 if fails > 0 else 0)
