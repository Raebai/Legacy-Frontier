# Task 5 report — self-damage + melee bugfixes

## Status: DONE (with one documented, deliberate deviation — see "Deviation" below)

## Current locations found (line numbers had shifted from the brief/audit)

- `Hero.gd::_primary_bolt()` — the `spell.set("caster", self)` call that was gated
  inside `if heal > 0:` lived at (pre-edit) lines ~1418-1421, not 1414-1417 as the
  brief said. Confirmed via grep for `_primary_bolt|bolt_heal|caster`.
- `Hero.gd::_melee()` — plain swing, ~line 1800 (pre-edit). No lunge at all.
- `Hero.gd::_on_melee_hit_frame()` — the arc-gated hit scan, ~line 1837-1888 (pre-edit),
  not 1829-1846 as the brief said.
- `Spell.gd::_ready()` (only sets up `collision_mask`, not the RID exclude — that build
  happens per-call in `_resolve_segment`, not `_ready`), `_resolve_segment()` line
  ~98-116 (RID exclude at ~108-109, matches brief), `_try_damage()` line ~126 (early-
  return target, matches brief's "147" region — my insertion sits right after the
  null/_dead guard, before the group check at the old line 147).
- `HIT_FRAME_FRACTION` — **does not exist in Hero.gd at all.** It's `CharacterRig.gd:21`
  (`const HIT_FRAME_FRACTION: float = 0.55`), inside the file the task explicitly says
  "Do NOT touch (the rig)". See Deviation below.

## Fix 1 — self-damage (bolt never hits its own caster)

**`Hero.gd::_primary_bolt`** (search `_primary_bolt`): moved `spell.set("caster", self)`
out of the `if heal > 0:` block so it now runs unconditionally for every spawned bolt
(burst-fanned copies included, since it's inside the `for i in maxi(burst,1)` loop, one
`set` per spell instance). `heal_on_hit` is still only set for the heal-flavoured classes.
Diff:

```gdscript
if bool(_cfg["throw_blade"]):
	spell.set("damage", int(_cfg["blade_damage"]))
# Caster is set for EVERY class's bolt (not just heal-flavoured ones)...
spell.set("caster", self)
# Flavour flags.
var heal: int = int(_cfg.get("bolt_heal", 0))
if heal > 0:
	spell.set("heal_on_hit", heal)
var chain: int = int(_cfg.get("bolt_chain", 0))
```

Verified Cleric/Warlock (bolt_heal classes) still set caster the same as before (now
via the unconditional line instead of the old conditional one) — no double-set, no
behaviour change for them.

**`Spell.gd::_try_damage`** (search `func _try_damage`): added an unconditional
backstop right after the existing `_dead or node == null` guard:

```gdscript
func _try_damage(node: Node) -> void:
	if _dead or node == null:
		return
	# Defensive backstop: a bolt must never damage its own caster...
	if node == caster:
		return
	if node.is_in_group("enemy") and node.has_method("take_damage"):
		...
```

This fires before any group check, so it protects the existing `elif node.is_in_group("hero")
and node != caster` friendly-fire branch too (that check is now redundant but harmless —
left it in place rather than removing working code outside the requested diff).

**`Spell.gd::_resolve_segment`** (search `_resolve_segment`): the raycast RID-exclude at
lines ~108-109 was *already* unconditional on `is_instance_valid(caster)` (never gated on
`heal_on_hit`) — no code change needed there, only a clarifying comment explaining it now
actually takes effect for every class since Fix 1 makes caster non-null universally.

## Fix 2 — melee auto-target + lunge + tightened impact

**Auto-target** (`Hero.gd::_on_melee_hit_frame`, search `_on_melee_hit_frame`): added a
new helper `_nearest_enemy_in_melee_range() -> Node2D` (nearest `Node2D` in group
`"enemy"` within `_melee_range`, else null). The enemy-hit loop now hits an enemy if
EITHER it's inside the strict facing-cone (`facing.dot(toward) > _melee_arc_dot`, existing
behaviour, unchanged) OR it IS the auto-targeted nearest enemy:

```gdscript
var nearest_enemy: Node2D = _nearest_enemy_in_melee_range()
for enemy: Node in get_tree().get_nodes_in_group("enemy"):
	...
	var in_arc: bool = facing.dot(toward) > _melee_arc_dot
	if not in_arc and enemy != nearest_enemy:
		continue
	...
```

This guarantees the nearest in-range enemy always connects (a click near an enemy
connects even if the cursor isn't exactly on them), while preserving the existing
wide-arc cleave behaviour for classes like Juggernaut (`melee_arc_dot: 0.0` — very
wide cone) that hit multiple enemies in one swing. Only the ENEMY loop was touched;
the destructible-prop and enemy-projectile-parry loops were left exactly as-is — the
brief and task both scope auto-target to "nearest enemy" specifically, and widening
those two loops too would be scope creep beyond what was asked/tested.

**Lunge on every swing** (`Hero.gd::_melee`, search `func _melee`): added
`MELEE_LUNGE_SPEED: float = 170.0` (new const, softer than combo's 200 / heavy's 190
since this is their shared baseline) and a `velocity.x = signf(_aim_dir.x) * MELEE_LUNGE_SPEED`
step inside `_melee()` itself — so it applies to the dedicated "melee" input action AND
every caller of `_melee()`. `_primary_melee_combo()` (Brawler) sets `velocity.x` again
right after calling `_melee()`, so the two assignments don't compound (last write wins,
no `+=`) — verified this is a direct assignment, not additive, before relying on it.
`_primary_heavy_swing()` (Juggernaut) doesn't call `_melee()` at all, so it's unaffected.

**Crescent-slash VFX** — already exists and already fires on every PUNCH/KICK swing,
with no Hero.gd/Spell.gd change needed. `CharacterRig.gd` has `SLASH_ARC_START/END/SPAN/
RADIUS_FACTOR` consts (lines 48-53) and draws the arc swoosh in its own `_draw()` for
every one-shot strike state, purely from animation phase — it doesn't care whether the
swing connects. Confirmed by reading `CharacterRig.gd:1002-1010`. I did not touch this
file; I'm reporting it as "already satisfied" rather than reinventing a second VFX system,
per the brief's own instruction to "reuse... keep it lightweight, don't invent a heavy
system."

**Whoosh SFX** — also already unconditional: `Sfx.play("melee_swing", 0.0, 0.08)` was
already the last line of `_melee()` before my edit, firing regardless of hit/miss. No
change needed; kept in place (now runs after the new lunge line).

**Small hitstop on every swing** (`Hero.gd::_on_melee_hit_frame`): added an `else`
branch after the existing `if hit_any:` block — a much lighter `Juice.on_hit` call
(`MELEE_SWING_HIT_STOP = 0.02`, `MELEE_SWING_SHAKE = 1.5`, both new consts) fires only
on a MISS, so a whiffed swing still has a little weight instead of reading as pure air.
The existing heavier on-connect cluster (`melee_hit` sfx + `MELEE_HIT_STOP` + the "ding")
is unchanged.

## Deviation: HIT_FRAME_FRACTION (~0.55 → ~0.35) — NOT changed, documented conflict

The brief's Step 4 says "lower `HIT_FRAME_FRACTION` to ~0.35... find the HIT_FRAME/
HIT_FRAME_FRACTION const" and lists it under files to modify in `Hero.gd`. It does not
exist in `Hero.gd` — it's `CharacterRig.gd:21` (`const HIT_FRAME_FRACTION: float = 0.55`),
a shared timing constant that also drives the strike wind-up/snap-to-extension curve at
`CharacterRig.gd:984-989` (`STRIKE_ANTICIPATION_FRACTION` → `HIT_FRAME_FRACTION` → full
extension → recovery) for EVERY class's PUNCH/KICK, not just the plain melee action.

The task's explicit constraint is: *"Only Hero.gd and Spell.gd (+ your new test) should
change. Do NOT touch the rig, movement, ring-out model, or Arena."* `CharacterRig.gd` is
literally "the rig" (the variable is named `rig: CharacterRig` throughout Hero.gd). I did
not edit it. Two reasons beyond "the constraint says so":

1. It's a shared const — retuning it would silently reshape the visual strike-arm-snap
   timing for combo/heavy-swing/every class, not just the reported plain-melee complaint,
   which is a bigger blast radius than a targeted bugfix task should take on unreviewed.
2. Faking the same effect from Hero.gd alone (a separate early Hero-side timer calling
   `_on_melee_hit_frame()` at 0.35× duration while leaving the rig's own signal at 0.55×)
   would make damage register measurably BEFORE the fist visually reaches the target —
   arguably a worse feel than the current 0.55, since the rig's arm-snap-to-extension is
   still keyed to 0.55. I judged that a mismatched half-fix was worse than no fix here.

Net effect: the two clearly in-scope changes (auto-target + lunge) directly address the
reported bugs ("their own click/melee attack... whiffs unless the cursor is exactly on
the target" — auto-target fixes this outright) and the "feels weird" complaint (lunge +
whoosh already existed + now a miss also has weight). The impact-timing-fraction is a
smaller polish item that needs the maker's sign-off to touch the rig file. Flagged as a
concern in the final reply.

## New test: `godot-project/tools/slice_test_selfdamage.gd`

Mirrors `slice_test_coop.gd` / `slice_test_coop_effects.gd` / `test_class_attacks.gd`
conventions (SceneTree runner, `_expect`, real `Hero.tscn` instantiation via
`(load(HERO_PATH) as PackedScene).instantiate()`).

Three test functions:

1. **`_test_bolt_sets_caster_for_every_class`** — swaps the live `/root/Net` autoload
   for a `FakeNet` stub (`is_active() -> true`) so `Spell._ready()`'s co-op friendly-fire
   `collision_mask |= 2` branch (the actual bug site) is live, without standing up a real
   ENet loopback session (no existing test in the repo does that; it would add real
   async-connection complexity for no extra coverage, since the bug and both fixes are
   deterministic given `Net.is_active() == true`). For MAGE(0)/ROGUE(1)/STORMCALLER(6)
   (`Hero.gd`'s `enum HeroClass` — the three bolt classes with no `bolt_heal`, i.e. the
   ones that previously spawned with `caster == null`): calls the hero's real `_cast()`,
   grabs the spawned `player_spell`, asserts `spell.caster == hero`, then feeds the bolt
   back at its own caster through the REAL `_try_damage(hero)` path and asserts hp/
   damage_pct are unchanged and the spell isn't marked `_dead` (i.e. it didn't consume
   itself hitting its own owner).
2. **`_test_try_damage_never_hits_caster`** — a bare unit test of the Spell.gd backstop
   in isolation (a `StubEnemy` in group `"hero"`, a bare `Spell.new()` with `caster` set
   to it, `_try_damage(stub)` called directly): confirms `take_damage` is never invoked
   and the spell survives — proves the guard is unconditional, not just incidentally
   true under the Net-active scenario above.
3. **`_test_melee_autotargets_nearest_enemy`** — BRAWLER hero at origin, `_aim_dir`/
   `facing` forced to `Vector2.RIGHT`, an enemy placed at `(-20, 0)` (within
   `_melee_range`=58, directly BEHIND the cursor — `facing.dot(toward) ≈ -1.0`, well
   under the 0.3 arc-dot threshold, so it would have whiffed pre-fix). Calls
   `_on_melee_hit_frame()` directly (no animation timing needed — that function only
   reads position/facing/range/arc, doesn't touch the rig) and asserts the enemy takes
   damage. A control step then moves the enemy out of range and re-calls, asserting no
   further hit (no false-positive/always-hit regression).

Print contract: `selfdamage tests: all PASS` on success (verified — see below).

## Test commands + output

```
godot-engine\Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --import
  -> clean, DONE/DONE, no errors (run before AND after the edits)

godot-engine\Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_selfdamage.gd
  -> selfdamage tests: all PASS
  (harness leaves its usual "WARNING: ObjectDB instances leaked at exit" / "ERROR: N
   resources still in use at exit" noise on quit — confirmed this is pre-existing
   harness behaviour, not introduced by this test, by running slice_test_coop.gd
   side-by-side and seeing the identical warning shape)
```

Full sweep — every `godot-project/tools/{slice*,m9,m10,m11,m12}*_test*.gd` and
`test_class_attacks.gd` (34 files total), run individually headless:

```
M9 tests: all PASS
M10 tests: all PASS   (its own deliberate malformed-JSON fallback test prints
                        "ERROR: Parse JSON failed..." to stderr by design — expected)
M11 tests: all PASS
M12 tests: all PASS
Slice0 sfx tests: all PASS
Slice0 targeting tests: all PASS
Slice1 blink tests: all PASS
Slice1 destructible tests: all PASS
Slice1 elements tests: all PASS
Slice1 enemy-attack tests: all PASS
Slice1 music tests: all PASS
Slice1 nova tests: all PASS
Slice1 rank tests: all PASS
Slice1 rig tests: all PASS
Slice1 telegraph tests: all PASS
Slice1 weapon tests: all PASS
Slice2 enemy-archetype tests: all PASS
Slice2 rogue tests: all PASS
Slice2 runloop tests: all PASS
Slice3 aiming tests: all PASS
Slice3 destructible-terrain tests: all PASS
Slice3 enemy-abilities tests: all PASS
Slice3 enemy side-on tests: all PASS
Slice3 parry tests: all PASS
Slice3 spell-collision tests: all PASS
Slice3 stage-hazard tests: all PASS
Slice3 versus tests: all PASS
Slice4 spell tests: all PASS
Slice5 class tests: all PASS
Boss tests: all PASS
Class-Q tests: all PASS
Climb spine tests: all PASS
Coop tests: all PASS
Coop-effects tests: all PASS
DEBRIS tests: all PASS
Floor tests: all PASS
Gear tests: all PASS (20 pieces)
Ground-crater tests: all PASS
Loadout tests: all PASS
movement tests: all PASS
rig tests: all PASS
ringout tests: all PASS
sandbox tests: all PASS
Status tests: all PASS
Summon tests: all PASS
Touch tests: all PASS
Class-attack tests: all PASS   <- exercises ALL 8 classes' primary attacks
                                   (melee classes 2/3/5 must LAND, not just fire) —
                                   direct regression check on the melee auto-target
                                   change; still green.
```

All green, zero failures.

## Self-review

- Only `Hero.gd` and `Spell.gd` changed among game source (`git status --short`
  confirms: `M godot-project/scripts/combat/Hero.gd`, `M .../Spell.gd`, plus the new
  test file + its Godot-generated `.uid` sidecar). `CharacterRig.gd`, movement code,
  the ring-out model, and Arena were not touched.
- Re-read `_try_damage`'s existing `elif node.is_in_group("hero") and node != caster`
  branch after adding the top-of-function backstop: confirmed it's now redundant-but-
  harmless (dead code path for the `node == caster` case specifically, still live and
  correct for the real cross-hero friendly-fire case) — left it rather than pruning
  working code outside the requested diff.
- Confirmed the lunge doesn't compound for `_primary_melee_combo()` (Brawler) by reading
  the exact assignment (`velocity.x = signf(...) * 200.0`, not `+=`) that runs immediately
  after `_melee()` returns — last write wins, no double-lunge.
- Confirmed `_primary_heavy_swing()` never calls `_melee()`, so the new unconditional
  lunge inside `_melee()` cannot affect Juggernaut's heavy swing.
- Confirmed via `test_class_attacks.gd` (pre-existing, unmodified) that all 8 classes'
  primary attacks still function post-edit, including the 3 pure-melee/cone classes that
  must actually LAND (not just fire) — direct regression coverage for the melee changes
  beyond my own new test.
- Did NOT modify `CharacterRig.gd` — documented why under "Deviation" above instead of
  silently skipping or silently violating the stated constraint.

## Concerns (surfaced in final reply too)

1. **HIT_FRAME_FRACTION (~0.55) was not lowered to ~0.35** — it lives in `CharacterRig.gd`
   ("the rig"), which the task explicitly says not to touch. Auto-target + lunge address
   the reported whiff/feel bugs directly; this is a smaller timing-polish item that needs
   either (a) the maker to explicitly lift the rig constraint for this one const, or (b)
   a follow-up task scoped to include `CharacterRig.gd` with its own review of the
   knock-on effect on every class's strike-arm animation curve.
2. The `elif node.is_in_group("hero") and node != caster` branch in `Spell.gd` is now
   provably dead-for-the-caster-case (superseded by the new top-of-function guard) but
   was left in place rather than simplified, to keep the diff minimal and reviewable.
