# A hero-shaped STUB for the drop-economy suites: exactly the two members
# `SpellGrant._install` writes, and nothing else.
#
# It exists because `set()` on an UNDECLARED property is a silent no-op in Godot 4.
# A stub assembled out of a bare `Node` plus `set("_signatures", ...)` would swallow
# both writes and every assertion about them would pass vacuously — the same shape
# of silent-green failure this repo has a scar from.
#
# Deliberately not a real `Hero.tscn`: Hero's `_ready` reaches autoloads, and
# `--script` harnesses do not register any. `tools/slice_test_drops.gd` covers the
# real-Hero half separately by asserting these member NAMES still exist on it.
#
# Leading underscore keeps `run_all_tests.py` from ever treating it as a suite.
extends Node

var _signatures: Array = []
var _hand: HandSlots = null
