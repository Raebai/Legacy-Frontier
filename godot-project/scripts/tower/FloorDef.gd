class_name FloorDef
extends Resource
## One floor of the climb — a typed test. The floor TYPE drives the rules; the
## encounter/theme/layout fields drive the content. Authored per-tower as .tres,
## or synthesized from depth math when no tower is set (sandbox / fallback).

enum FloorType { COMBAT, ELITE, BOSS, REST, PVP }

@export var floor_type: FloorType = FloorType.COMBAT
## Encounter (replaces the old f(floor) depth math).
@export var enemy_budget: int = 4       # total enemies this floor; 0 = REST (no combat)
@export var concurrent_cap: int = 3     # max alive at once
@export var brute_chance: float = 0.35  # biases the archetype roll toward brutes
## TRASH HP scaling. HELD AT 1.0 BY POLICY on every authored floor — per the spec,
## "higher floors add modifiers, not HP. HP scaling makes fights longer, not
## harder, and long is the enemy of chaos on a phone." Depth escalates through the
## archetype MIX (`WaveDef.archetypes`, `brute_chance`) and through wave shape.
## The field survives because the guardian still wants a depth curve — see
## `boss_hp_multiplier` — and because a one-off floor may want a deliberate lie.
@export var hp_multiplier: float = 1.0
## THE FLOOR'S SHAPE: 3-5 escalating waves, then the boss. Leave EMPTY and
## Encounter synthesizes a wave list from `enemy_budget` / `concurrent_cap`
## (Encounter.synthesize_waves), so a FloorDef authored before waves existed —
## or a synthesized fallback floor — still plays as a wave fight.
@export var waves: Array[WaveDef] = []
## THE SURGE BEAT between one wave handing off and the next opening, in seconds.
## Deliberately SHORT: this is a loud reward flourish (the room reacts, the next
## wave is already visibly being drawn in) with the previous wave's last bodies
## usually still alive through it — not silence. Kept under the old `wave_break`
## name because the FloorDef data + the wave tests both address it by that name.
@export var wave_break: float = 0.85
## Boss HP as a fraction of the guardian's full strength. <= 0 derives it from
## floor_type (Encounter.boss_scale_for_type): a COMBAT floor gets a lean
## mini-guardian, ELITE a bigger one, BOSS the colossus at full size.
@export var boss_scale: float = 0.0
## GUARDIAN HP depth curve, applied ONLY to the floor's boss. This is where the
## depth-HP ramp lives now that trash HP is pinned at 1.0: a longer fight is
## legitimate for the one big committed duel that ends a floor, and illegitimate
## for the twelve bodies you are supposed to be shredding. <= 0 falls back to
## `hp_multiplier` so a pre-existing FloorDef scales its boss exactly as before.
@export var boss_hp_multiplier: float = 0.0
## Environment + layout (null = inherit the tower default, resolved at build).
@export var theme: EnvTheme = null
@export var layout: LayoutDef = null
## THIS FLOOR'S DEPTH IN THE TOWER (1-based). 0 = "not told", in which case
## Encounter falls back to the live GameState floor and then to 1.
##
## It exists because DEPTH IS THE MODIFIER DIAL. The spec's rule is "higher floors
## add modifiers, not HP", and a modifier count has to be computed from something —
## but `Encounter.run_floor(floor_def)` is handed a FloorDef and nothing else, so
## until now the encounter genuinely did not know which floor it was building. An
## authored field is better than an autoload lookup for the same reason every other
## floor rule lives here: it travels with the data, so a headless test can build
## "floor 7" without a run being active.
@export var depth: int = 0
## Loose escape hatch for per-floor rules (e.g. "no_crates", "boss_gate").
##
## TWO TAGS ARE READ BY THE BOSS ROSTER (BossRoster.parse_tags):
##   "boss:<id>"  — pin this floor's boss instead of rolling one ("boss:illuminator")
##   "mod:<id>"   — force a modifier onto it ("mod:mirrored"); stacks with the roll
##   "no_mods"    — this floor's guardian rides clean, whatever its depth says
## Anything else is ignored, so the field stays the loose escape hatch it was.
@export var special_tags: Array[String] = []
