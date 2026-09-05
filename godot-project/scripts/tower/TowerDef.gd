class_name TowerDef
extends Resource
## A whole tower: an ordered spine of typed floors + a default environment.
## Authored as a .tres (data/towers/*.tres). A new tower = a new file, no code.

@export var id: String = "ashspire"
@export var display_name: String = "The Ashen Tower"
@export var theme: EnvTheme = null            # default theme for floors that don't override
@export var floors: Array[FloorDef] = []      # ordered; floors.size() == the AUTHORED spine

## ══ DOES THE TOWER END? ═══════════════════════════════════════════════════════
## Maker, 2026-09-04: *"revamp the tower so thats its infinite and you are scored on
## like how high you get"*.
##
## `floors` is the AUTHORED SPINE and stays exactly that — ten hand-tuned floors,
## twice re-cut on playtest notes. When this is true, the climb does not stop at the
## end of that array: `GameState.floor_def_for` synthesizes an ASCENT floor for every
## depth past it (`GameState.ascent_floor_def`), runs it through the same
## `FloorGen.vary_floor` an authored floor gets, and hands downstream a `FloorDef`
## that is indistinguishable from an authored one.
##
## ⚠ IT DEFAULTS TO FALSE, AND THAT IS LOAD-BEARING. `GameState.build_default_tower()`
## is called directly by eight tools and suites which assert the authored numbers
## against it (`slice2_test_runloop` pins `floors.size() == TOTAL_FLOORS`;
## `slice_test_climb` pins that clearing the last floor CONQUERS and does not emit
## `floor_advanced`). So the spine builder keeps returning a finite tower, and
## `GameState._load_or_build_tower()` — the only path the *game* takes — flips this
## on. Same split, and the same argument, as `FloorGen.apply` already uses: the
## authored table stays the thing that is asserted, and the thing applied at play
## time stays the thing that is played.
@export var endless: bool = false

## THE CLIMB SEED THIS TOWER WAS DRAWN WITH. Stamped by `FloorGen.vary_tower`, 0 on a
## tower that has never been through the generator.
##
## It exists because an ascent floor has to be derived somewhere, and reading
## `FloorGen.last_seed` at that moment would be reading a global that any other climb
## (or any tool in the same process) may have moved since. Carried ON the tower, the
## floor at depth 37 is a pure function of `(id, depth, climb_seed)` — which is also
## what makes it safe in co-op, where both peers must derive the same room from the
## same number and `resolve_seed()` already pins that number to 0.
@export var climb_seed: int = 0
