# Mobile-first casting UX — typed slots, direction aim, forgiveness by shape

**Date:** 2026-07-27
**Branch:** `stickman-integrate`
**Status:** design (READ-ONLY recon) → awaiting maker review → plan → build
**Scope:** how a player CHOOSES and FIRES a spell, on a phone and on a desktop, with 24 spells in the tree.

---

## 0. TL;DR

- **Recommended model: (a) a capped, TYPED 4-slot equipped loadout — one on-screen button per slot.** The four hardcoded ability keys we have today (`blast`/`blink`/`nova`/`ultimate`) collapse INTO those four slots, so the button count goes *down* (6 touch targets → 5) while the spell count reachable from those buttons goes *up* (5 fixed → any 4 of 24).
- **Rejected:** radial/flick-select (it eats the direction channel that aiming needs), modal two-tap (doubles the cost of the most frequent action — it is literally today's debug affordance), gesture-per-button (invisible state, collides with aim).
- **The aim tension resolves with one rule:** *aim is a DIRECTION, never a TARGET. Forgiveness is bought with SHAPE (width, radius, arc, placement preview), never with correction toward an entity.* Everything that reads an entity's position to change a spell's direction is banned — including the `Targeting.aim_direction` snap the touch path uses today. Everything that changes a spell's SIZE is allowed and is where the entire mobile-forgiveness budget goes.
- **Lands in the SpellPlayground first** (that is what the maker F5s), behind a `force_visible` touch pad, before the real `Hero`.

---

## 1. Ground truth — what actually exists today (verified on this branch)

### 1.1 The input action map (`godot-project/project.godot`)

19 actions. Combat-relevant ones and their bindings:

| action | binding | polled by |
|---|---|---|
| `move_left` / `move_right` / `move_up` / `move_down` | A/D/W/S + arrows | `Hero._physics_process`, `Player.gd`, `TouchControls` |
| `jump` | W + Up | `Hero.gd:546,576` |
| `dash` | Space | `Hero._update_input_buffer` |
| `cast` | Mouse LEFT | `Hero.gd:517` (hold-to-repeat) |
| `melee` | F | buffered (`Hero.gd:676`) |
| `parry` | Mouse RIGHT | `Hero.gd:515` |
| `blast` | Q | buffered |
| `blink` | R | buffered |
| `nova` | T | buffered |
| `ultimate` | G | `Hero.gd:513` → `_cast_signature()` |
| `cycle_signature` | V | `Hero.gd:511` |
| `cycle_element` / `cycle_colourway` / `switch_class` / `fly` | X / C / Tab / Shift | `Hero.gd:505-509` (debug + cosmetic) |
| `cycle_music` | M | `Music.gd:195` |
| `talk` / `chat` / `ui_cancel` | E / Enter / Esc | hub, NPCs, menus |

**That is 12 combat actions the hero polls.** It does not fit two thumbs, and it does not scale — every new ability today costs a new key.

### 1.2 `TouchControls.gd` — EXISTS ON THIS BRANCH

`godot-project/scripts/combat/TouchControls.gd`, committed as `d5d4f28` ("Mobile: two-thumb touch controls + auto-aim"). `git branch --contains d5d4f28` → `stickman-integrate` (current), `stickman-finalise`, `v2.0-tower`. **It is not v2.0-tower-only.** (A second copy lives in the `.claude/worktrees/stickman-final` worktree — same file, ignore it.)

What it does:
- `CanvasLayer` at layer 70, self-hides unless `DisplayServer.is_touchscreen_available()` or `force_visible` is set.
- **Left thumb:** a DYNAMIC joystick (spawns where you press in the left 45% of the screen). Horizontal = analog `move_left`/`move_right` via `Input.action_press(action, strength)`; push down past 0.6 = `move_down` (the ragdoll duck).
- **Right thumb:** a fixed arc of 5 buttons — `CAST`, `DASH`, `Q`(`blast`), `G`(`ultimate`), `BLINK`. Plus a `JUMP` button on the left.
- Feeds the SAME named actions via `Input.action_press` / `action_release`, so it composes with `Hero` with zero combat-code changes. That seam is correct and must be preserved.
- Instantiated at `Arena.gd:439` and `VersusArena.gd:499`. **NOT** in the SpellPlayground.
- Tested by `godot-project/tools/slice_test_touch.gd`; previewable via `godot-project/tools/touch_capture.gd`.

**Three defects found while reading it — fix these regardless of which model wins:**

1. **The JUMP button is dead in combat.** `_add_button("JUMP", "move_up", ...)` presses the `move_up` *action*. `Hero.gd:546` polls the `jump` action. `Input.action_press("move_up")` does not set `jump` — they are separate actions that merely share a physical key. So on a touch device the hero never jumps. (`Player.gd:78` in the hub polls `jump` **or** `move_up`, which is why nobody caught it.)
2. **No melee and no parry on touch.** Two of the hero's core verbs (and the whole Brawler/Juggernaut identity) are unreachable with a thumb.
3. **No cooldown feedback on the buttons.** `AbilityBar` draws cooldowns bottom-centre; on a phone your thumbs are on the buttons, not on the centre of the screen. (Already flagged as deferred in `.superpowers/sdd/progress.md:127`.)

### 1.3 The playground — `scripts/spike/SpellPlaygroundController.gd`

- Cycles **all 24** spells with Q/E (`SpellLibrary.build_all()`), casts with RMB or F **toward `get_global_mouse_position()`**, `_cast_cd = 0.35`.
- **It reads raw keycodes**: `Input.is_key_pressed(KEY_A/KEY_D/KEY_W/KEY_S/KEY_SPACE)` at lines 189-197 and 236-243, plus a `match event.keycode` block at 282-313 (Q/E/F/Shift/C/B/H/K/R/Tab/brackets/number keys).
  **Correction to the brief:** the repo greps clean of the *string* `physical_keycode` in scripts, but `scripts/spike/*` is NOT action-based — it is raw `KEY_*`. The spike is throwaway, so this was fine; it is not fine once the shipping casting UX lives there. Moving the playground onto actions is a prerequisite of this work, not a nice-to-have.
- `SpikeFigure` public verbs already exist: `punch()`, `dash(dir)`, `parry()`, `cast(dir, pose)`, `blink_to(dest)`, `hit()`, `kill()`. Good — the playground can drive the real UX without touching game code.

### 1.4 The spell + cast data path

- `SpellDef` (Resource): `id, display_name, kind, element, mp_cost, cooldown, damage, length, width, radius, reach, count, cast_time`. `Kind` is an append-only enum of 16 spectacles.
- `SpellLibrary.build_all()` → the 24 spells. `SpellLibrary.build_for_class(class_id)` → 2-5 signatures per class.
- `SpellCaster.cast(spell, arena, caster_pos, target_pos, fallback_color, effect, caster)` — one static dispatch seam, already used by BOTH `Hero._finish_summon` and the playground. **This is the single chokepoint every casting UX must go through, and it already takes a `target_pos`, not a target node.** Excellent foundation.
- `Hero._cast_signature()` → `_begin_channel` (0.4s levitating windup for `cast_time > 0`) or `_begin_summon` (0.42s grounded spell circle; 0.22s for rush/blink). Both are *committed* — no input during the windup.

### 1.5 The aiming code today — where the tension is already violated

- Desktop: `Hero.gd:480` reads `get_global_mouse_position()` every frame → `_aim_dir`. Placed spells (`_begin_summon` line 951, `_summon_target`) use the raw cursor point. **Pixel aim.**
- Touch: `Hero.gd:475-478` calls `Targeting.aim_direction(pos, enemies, fallback)` → `Targeting.nearest()` → **a hard snap to the nearest enemy.** That is auto-aim. It directly contradicts magic-overhaul rule 1 ("NO AUTO-AIM / NO HOMING on ANY spell"), which Phase 2a already enforced *inside* the spells (RuneOrbs homing was killed) but never enforced on the *caster's aim*.
- `Targeting.assisted_aim()` (a ±18° cone bend toward an enemy, `bend=0.6`) exists and is documented in `progress.md:377` as the mobile plan. **It is soft auto-aim and is also out** under the current rule set.
- Melee auto-targets the nearest enemy in range (`progress.md:29`).

So today: the desktop path breaks the mobile-first rule and the touch path breaks the no-auto-aim rule. Section 4 resolves both with one seam.

### 1.6 What the maker already agreed (backlog)

Loadout must be **capped**; the cap and the available spells are gated by **class + progression**; the **choice happens out of combat** (hub/lobby). Today `SpellLibrary.build_all()` returns everything and the playground cycles freely mid-combat. That is what must go.

---

## 2. The four models, judged

Criteria, in the order that matters for this game: **thumb reach → behaviour under Cuphead-hard pressure → button count → scaling 4→24 → discoverability → desktop mapping.**

### (a) Capped equipped loadout, one button per slot

| | |
|---|---|
| Buttons | 4 spell buttons + jump; dash moved to a joystick gesture (see §3.3). **5 touch targets, down from 6.** |
| Thumb reach | Fixed positions in the bottom-right arc — the strongest property of the model. Muscle memory is spatial and never moves. |
| Under pressure | Best of the four. One tap = one cast. Zero mode state, zero selection latency, no way to "cast the wrong thing because the menu was still open". |
| Scales 4→24 | Via the loadout, not the input. 24 spells live in the grimoire; 4 are equipped. Growing the cap to 5 later is a data change (`for i in _slots.size()`), not an input redesign. |
| Discoverability | High — the buttons are always visible, labelled, and show cooldown. |
| Desktop | 1:1. Four keys (LMB / Q / RMB / G, plus 1-4 as aliases) that *already* carry the muscle memory of the abilities they replace. Desktop additionally gets cursor precision on placed spells (§4.3) — strictly better than mobile, not a port. |

### (b) Radial / flick-select (hold a button, flick a direction, release to cast)

| | |
|---|---|
| Buttons | 1. The headline win. |
| Thumb reach | Fine — one big target. |
| Under pressure | **Fatal flaw: the flick direction is consumed by SELECTION, so it cannot also be the AIM.** In a game where aim is a direction (§4), radial and aiming compete for the same input channel. You would have to select with the right thumb and aim with the left, or aim before you know which spell you picked. Both are worse than a button. |
| | Secondary problem: hold→flick→release is ~250-400 ms of selection *before* a 0.42 s summon windup and *before* the spell travels. Against telegraphed boss patterns that is a full extra beat of commitment. |
| | Tertiary: mis-flicks. 8 sectors on a 66 px radius under panic = wrong-spell casts, and a wrong cast costs MP + cooldown. |
| Scales | Genuinely well (8 per ring, nested rings for more) — its only real advantage over (a). |
| Discoverability | Good (the ring is drawn). |
| Desktop | Awkward — radial menus on mouse are fine, on keyboard they are a worse version of number keys. |
| **Verdict** | **Reject as the combat model.** Its scaling advantage is unnecessary once the loadout is capped at 4 — we are solving 4-on-screen, not 24-on-screen. |

### (c) Modal select-then-cast (two taps)

| | |
|---|---|
| Buttons | 1-2. |
| Under pressure | Worst. It doubles the input cost of the single most frequent action, and it introduces a mode you can be wrong about. |
| | This is exactly what the playground does today (Q/E cycle, then F to cast) — the affordance the maker explicitly called a debug tool, not a game UX. |
| Scales | Yes, but so does (a)'s grimoire, and (a) pays the cost out of combat instead of in it. |
| **Verdict** | **Reject for casting.** Keep the shape only where it belongs: the out-of-combat grimoire (§3.4) IS a select-then-confirm UI, and there it is correct. |

### (d) Context / gesture casting (tap vs hold vs swipe on the same button)

| | |
|---|---|
| Buttons | 1-2, each carrying 3 spells. |
| Under pressure | Hold-vs-tap discrimination requires a ~200 ms threshold, which means either a laggy tap or a twitchy hold. Both are bad in a dodge-the-tell game. Swipe-on-button collides with the aim gesture and with the joystick. |
| Discoverability | **Worst of the four, and not fixable.** The state is invisible: nothing on screen tells you that holding slot 2 produces a different spell. It is the classic "hidden depth that 90% of players never find". |
| Scales | 3× per button, but the ceiling is low and the cost is player confusion. |
| **Verdict** | **Reject as a spell-selection mechanism.** Keep exactly ONE gesture, and only where the gesture is fully *visible* while you make it: **hold a placed-spell slot → a ghost preview of the impact point slides along your aim; release to commit** (§4.3). The preview is the discoverability. |

### Decision

**(a), with one typed-slot refinement and one borrowed gesture.** The refinement is what makes it survive class-switching; the gesture is what makes placed spells work without a cursor.

---

## 3. The recommended design

### 3.1 TYPED slots — the structural claim

Four slots, each with a fixed **role**, a fixed **screen position**, and a fixed **key**. A slot only accepts spells of its role.

| slot | role | today's equivalent | MP? | example spells |
|---|---|---|---|---|
| 1 | **PRIMARY** — light, spammable, no MP, short cd | `cast` / `melee` | no | bolt, frost cone, melee combo, heavy swing, dagger flurry |
| 2 | **AREA** — a zone / bombardment / barrage you place or throw | `blast` (Q) | small | meteor sigil, blizzard, void zone, avalanche, consecrate, boulder hurl |
| 3 | **MOBILITY / DEFENCE** — reposition or deny | `blink` (R), `parry` (RMB), `nova` (T) | small | blink strike, rock wall, ice wall, nova, parry, rush |
| 4 | **SIGNATURE** — the spectacle. The only heavily MP-gated slot | `ultimate` (G) | yes | zoltraak, judgment, heaven's verdict, chidori, chain lightning |

Why typed and not four free slots:

- **Muscle memory survives a class change.** Slot 3 is always "get out of trouble", on Cryomancer and on Brawler alike. With free slots, switching class re-teaches your thumbs.
- **It is the progression gate the maker already agreed to.** "Which spells can go in which slot, for this class, at this rank" is a clean, authorable rule. Free slots would need an arbitrary cost/point system.
- **It prevents the degenerate loadout** (four ultimates, no primary) without a balance patch.
- **It gives the HUD a stable meaning** — four fixed icons, four fixed cooldown rings.

Implementation: add `@export var slot: int = -1` to `SpellDef` (append-only, safe), and a `SpellSlots.slot_kind_of(spell)` fallback table keyed on `SpellDef.Kind` so the 24 existing code-built spells classify with zero authoring:

```
BEAM, DIVINE_RAY, CONVERGENCE, RUSH, CHAIN        -> SIGNATURE
METEOR, ZONE, MISSILES, BOULDER, PILLAR, FLURRY   -> AREA
WALL, ICE_WALL, BLINK_STRIKE, NOVA, TETHER        -> MOBILITY
(the per-class primaries in Hero.CLASS_CONFIG)    -> PRIMARY
```

A spell may declare an explicit `slot` to override the table (e.g. `boulder_hurl` could be MOBILITY-flavoured for a Juggernaut build). One spell may be eligible for two slots; it may only be *equipped* in one at a time.

**Cap = 4.** Recommend shipping 4. A 5th slot is a future progression unlock and costs no input work.

### 3.2 The combat control set — final

**Touch (5 targets + 1 joystick, down from 6 + 1):**

```
LEFT THUMB                          RIGHT THUMB
  dynamic joystick                    [1] PRIMARY   (corner, biggest, hold-to-repeat)
    horizontal = analog move          [2] AREA
    push down  = duck / ragdoll       [3] MOBILITY
    double-tap-flick = DASH  (new)    [4] SIGNATURE
  JUMP button                         (hold a placed-spell slot = drag the impact
                                       preview along your aim; release to cast)
```

**Keyboard / mouse (unchanged muscle memory):**

```
A/D move · W/Up jump · S duck · Space dash
slot_1 = Mouse LEFT  or 1
slot_2 = Q           or 2
slot_3 = Mouse RIGHT or 3
slot_4 = G           or 4
aim    = cursor (placed spells clamp to spell.reach)
```

**Gamepad (free, same seam):** left stick move, A jump, B/RB dash, X/Y/RT/LT = slots 1-4, **right stick = aim direction**.

**Removed from combat entirely:** `cycle_signature` (V) — the loadout is chosen out of combat, so there is nothing to cycle. `cycle_element` (X), `cycle_colourway` (C), `switch_class` (Tab), `fly` (Shift) — debug/cosmetic; move behind the pause menu. `cycle_music` (M) stays where it is, in the `Music` autoload, not in the hero.

**Dash as a joystick double-tap-flick** is the one genuinely new interaction and the reason the button count drops. It is defensible: dash direction already comes from `_move_dir` (`Hero.gd:545`), i.e. from the movement thumb, so putting the trigger on the movement thumb *reunites* the trigger with its direction. It is also a known mobile idiom.
**Fallback if F5 says it misfires:** drop to 3 spell slots + a dash button, or add a settings toggle "Dash button: on". Both are one-line changes because the slot loop is `for i in _slots.size()`. Call this at playtest, not now.

### 3.3 Cooldown, MP and identity on the buttons

Each slot button draws: the spell's element colour as its fill, a 1-2 word name, a radial cooldown wipe, and a dim state when MP can't cover it. This is a straight port of `AbilityBar._draw_slot` (which already consumes a `{name, key, remaining, total, enabled}` dictionary) onto the touch button. `Hero.ability_hud_state()` shrinks from 7 entries to 4 and both HUDs consume it — one contract, two renderers.

### 3.4 The grimoire — where the choice happens (out of combat)

New `scripts/ui/Grimoire.gd` + `scenes/ui/Grimoire.tscn`, **modelled exactly on the existing `Loadout.gd`** (autoload `CanvasLayer`, built in code, dim + tap-away + Esc close, writes to `GameState`, live-previews on the hub figure). This is the established pattern in this repo; do not invent a second one.

- Four rows, one per slot. Tap a slot → the eligible spells for `(slot, class, progression)` are listed; locked ones are dimmed with their unlock condition visible ("Rank 3" / "Cryomancer only"). Tap to equip.
- Writes `GameState.spell_loadout: Array[String]` — four spell **ids**, persisted alongside the existing `GameState.loadout`. Ids, not Resources, so saves survive spell re-tuning.
- Entry points: the hub **Armory** station (walk-up + E, next to the gear loadout — `ArmoryStation.gd` already does this), the lobby, and a debug key in the playground.
- `SpellLibrary.build_all()` stops being a gameplay source and becomes what it already is by name: the *audit* list, consumed by the grimoire and the tests.

This is the (c) modal model, correctly located: two taps for a decision you make once, zero taps for a decision you make sixty times a fight.

---

## 4. THE AIM TENSION — resolved

Two hard rules that appear to contradict:

- **R1 (CLAUDE.md, locked):** "Mobile-first input... never design something that requires pixel-perfect mouse aim."
- **R2 (magic overhaul, rule 1):** "NO AUTO-AIM / NO HOMING on ANY spell. Everything aims manually; dodging is player skill."

They only contradict if you assume forgiveness must come from *correction*. It does not.

### 4.1 The rule

> **Aim is a DIRECTION, never a TARGET.
> Forgiveness is bought with SHAPE. Never with correction toward an entity.**

**Banned (violates R2) — anything that reads an entity's position to change where a spell goes:**
- nearest-enemy snap → **delete `Targeting.aim_direction` from the hero's touch path (`Hero.gd:475-478`)**
- cone-bend aim assist → **`Targeting.assisted_aim` is out of every hero path** (it may stay in the file for enemy AI, which is allowed to aim at the player)
- homing / re-targeting projectiles (already killed in Phase 2a — this closes the caster-side hole)
- melee "find nearest target and lunge at it"

**Allowed (satisfies R1) — anything that changes a spell's SIZE or SHAPE, symmetrically, without reading entity positions:**
- wider beams, bigger blast radii, wider melee arcs
- fans and arcs instead of single lines
- a visible placement preview you drag with your thumb
- a longer telegraph (which also *helps* the enemy dodge yours — symmetric, therefore fair)

The distinction is legible in one sentence: **a spell may be easy to hit with; it may never decide who it hits.**

### 4.2 Aim source — one seam, three inputs

`CastInput.aim_dir(hero) -> Vector2`, resolved in priority order:

1. **Touch:** the move joystick's current heading. If the stick is neutral, the last non-zero heading; if never moved, `facing`. (This is why the joystick is analog and 360° in `TouchControls` even though movement is horizontal — the vertical axis is already read for the duck; it becomes the aim's Y too.)
2. **Gamepad:** right stick, falling back to (1).
3. **Mouse/keyboard:** `(get_global_mouse_position() - global_position).normalized()`.

All three produce a plain unit vector. **No branch anywhere downstream knows which device produced it.** That is the whole point — `Hero._aim_dir`, `SpellCaster.cast`, the cast poses, the camera peek, and the tests all consume one value.

### 4.3 Placed spells — direction + reach, not a pixel

`SpellDef.reach` already exists and is already the intended semantic ("how far from the caster a placed spell lands toward the aim"). Today `Hero._begin_summon` ignores it and uses the raw cursor (`_summon_target = get_global_mouse_position()`, line 951).

New rule: **`target_point = origin + aim_dir * reach_now`**, where `reach_now` is:

- **Touch:** starts at `spell.reach`. While the slot button is HELD, a ghost preview of the impact footprint is drawn at `origin + aim_dir * reach_now`, and dragging the joystick sweeps both the direction and (with the stick's magnitude) the distance in `[0.35, 1.0] × reach`. Release = cast. Tap without holding = cast at the default `reach`. **The preview IS the aim UI, and it is fully visible while you use it** — this is the one gesture borrowed from model (d), and the only one that earns its keep.
- **Desktop:** `reach_now` = the cursor distance, **clamped to `spell.reach`**. So the cursor is a *precision refinement of the same value*, not a different mechanism. Desktop gets strictly more control; nothing degrades.
- **Gamepad:** right-stick magnitude, same as touch.

`Hero.BLAST_MAX_RANGE = 480.0` already encodes exactly this clamp for meteor ("skill-shot, not a cross-stage snipe") — this generalises it to every placed kind and moves the number onto the SpellDef where it belongs.

### 4.4 Forgiveness by shape — the auditable number

Pick one number and hold every spell to it:

> **A spell must connect with a target that sits within ±8° of the aim direction, at that spell's effective range.**

±8° at 300 px ≈ ±42 px of half-width. Formally, every offensive spell must satisfy:

```
effective_half_width(spell) >= tan(deg_to_rad(8.0)) * effective_range(spell)
```

...where `effective_half_width` is `width * 0.5` for beams/rushes, `radius` for placed AoE / nova / zone / pillar, and the fan half-angle × range for missiles/chain/flurry; and `effective_range` is `length` for beams, `reach` for placed, `reach` for chain hops.

- This is **testable headlessly for all 24 spells** (§6) and it turns "does aim feel forgiving?" from a vibe into a regression test.
- Spells that fail get **wider**, not smarter. E.g. `frostpiercer` (`length 1250, width 22` → half-width 11 vs required ~176) is the archetypal fail: a 1250 px needle is a desktop-cursor spell. Either its width goes up hard or its length comes down. That is a balance conversation the audit will force, honestly, on all 24 at once.
- ±8° is a starting knob (`Tuning.aim_forgiveness_degrees`). Tune at F5.

**Why this does not break "everything is dodgeable":** widening is symmetric and static. The telegraph, the windup (0.42 s summon / 1.0-1.3 s channel), and the travel time are untouched — those are what make a spell dodgeable, and this spec adds nothing that shortens them. A wide beam you can see coming for a second is fair; a thin beam that curves toward you is not. We are trading *precision required to aim* for *precision required to dodge*, which is the correct trade for a mobile brawler with hard bosses.

### 4.5 Aim latch

On slot press, latch `_aim_dir` for the whole windup and the cast. No re-aim mid-summon, no re-target mid-flight, ever. Two reasons: a 0.42 s committed windup that silently re-aims is a lie about commitment, and a thumb resting on an analog stick wobbles.

### 4.6 Melee

Melee today auto-targets the nearest enemy in range (`progress.md:29`). Under R2 that is a violation of the same family. **Recommend:** melee keeps its `MELEE_ARC_DOT` arc (an arc is shape-forgiveness — allowed, and generous) and its lunge goes along `aim_dir`, not toward a found body. **Maker call**, flagged explicitly because it will change how punching feels and the arc may need widening to compensate.

---

## 5. Exact changes

### 5.1 `godot-project/project.godot` — input map

**ADD (4 actions):**

| action | events |
|---|---|
| `slot_1` | Mouse button 1 (LEFT), physical key `1` (49) |
| `slot_2` | physical key `Q` (81), physical key `2` (50) |
| `slot_3` | Mouse button 2 (RIGHT), physical key `3` (51) |
| `slot_4` | physical key `G` (71), physical key `4` (52) |

**ADD (optional but recommended — gamepad/keyboard aim, no mouse required):**

| action | events |
|---|---|
| `aim_left` / `aim_right` / `aim_up` / `aim_down` | joypad axis 2/3 (right stick) ± |

**KEEP but STOP POLLING in `Hero.gd`:** `cast`, `melee`, `parry`, `blast`, `blink`, `nova`, `ultimate`, `cycle_signature`, `cycle_element`, `cycle_colourway`, `switch_class`, `fly`.

Deliberately **do not delete them in this change.** `slot_1` binds LMB and `slot_3` binds RMB, so the old `cast`/`parry` actions would still fire on the same physical input if something still polled them — leaving them defined and unpolled keeps the diff small and keeps `tools/slice*_test_*.gd` (43 suites) from breaking on a missing action. Delete them in a follow-up cleanup commit once the sweep is green on the new names.

**UNCHANGED:** `move_*`, `jump`, `dash`, `talk`, `chat`, `cycle_music`, `ui_cancel`.

### 5.2 New scripts

| file | what |
|---|---|
| `godot-project/scripts/combat/CastInput.gd` | `class_name CastInput extends RefCounted`, **all static**. THE SEAM. `aim_dir(owner) -> Vector2` (touch / gamepad / mouse, §4.2); `placed_point(origin, aim, reach, magnitude) -> Vector2` (§4.3); `slot_just_pressed(i) -> bool`; `slot_held(i) -> bool`; `dash_just_pressed(owner) -> bool` (button OR joystick double-tap-flick). **Never touches `KEY_*`, never touches `Targeting`.** Pure functions → headless-testable without a scene. |
| `godot-project/scripts/combat/SpellSlots.gd` | `class_name SpellSlots extends RefCounted`, static. `enum SlotKind {PRIMARY, AREA, MOBILITY, SIGNATURE}`; `slot_kind_of(spell) -> int` (explicit `spell.slot`, else the Kind table §3.1); `eligible(slot_kind, class_id, rank) -> Array[SpellDef]`; `default_loadout(class_id) -> Array` (4 SpellDefs, built from `SpellLibrary`); `resolve(ids: Array[String]) -> Array` (id → SpellDef, with a safe fallback to the class default on an unknown id). |
| `godot-project/scripts/ui/Grimoire.gd` + `scenes/ui/Grimoire.tscn` | The out-of-combat picker (§3.4). Clone `scripts/Loadout.gd`'s structure. Register as an autoload named `Grimoire` next to `Loadout`. |

### 5.3 Changed scripts

**`scripts/combat/SpellDef.gd`** — append `@export var slot: int = -1` (-1 = derive from `kind`). Append-only; no existing field moves.

**`scripts/combat/TouchControls.gd`**
- Right arc: replace the 5 hardcoded `_add_button("CAST"/"DASH"/"Q"/"G"/"BLINK", ...)` calls with a loop over 4 slot buttons bound to `slot_1..slot_4`.
- **Fix the jump bug:** `_add_button("JUMP", "jump", ...)` (was `"move_up"`).
- Joystick: keep the analog move + duck; feed the full 360° heading to `CastInput` as the aim source; add double-tap-flick → `dash`.
- Buttons gain the cooldown ring + element tint + MP dim, fed by `hero.ability_hud_state()` (§3.3).
- Add the hold-to-place preview for slots whose spell is a placed kind.
- Keep `force_visible`, keep the `Input.action_press` seam, keep the const knobs.

**`scripts/combat/Hero.gd`**
- `_physics_process`: delete the six one-off ability polls (lines 505-517) and the `_update_input_buffer` action list (line 676); replace with a single `for i in 4: if CastInput.slot_just_pressed(i): _try_slot(i)`, plus the existing buffer applied per slot.
- `_touch_aim()` / the `Targeting.aim_direction` branch (lines 419-422, 475-478) → **deleted**, replaced by `_aim_dir = CastInput.aim_dir(self)`.
- `_begin_summon` / `_begin_channel`: `_summon_target = CastInput.placed_point(global_position, _aim_dir, spell.reach, mag)` instead of `get_global_mouse_position()`.
- `_cast_signature()` generalises to `_cast_slot(i)`; the MP gate applies only to slot 4 (and to any equipped spell with `mp_cost > 0`).
- `_signatures` / `_signature_index` / `_cycle_signature()` → replaced by `_slots: Array[SpellDef]` (4) + `_slot_cd: Array[float]` (4). `configure_class` loads `SpellSlots.default_loadout(cls)` then applies `GameState.spell_loadout` over it — exactly mirroring how `_apply_gamestate_loadout` already layers gear over the class base.
- `ability_hud_state()` returns **4** entries.

**`scripts/combat/AbilityBar.gd`** — no logic change (it loops `_slots`), but the 4-slot layout wants bigger slots. Bump `SLOT_SIZE` and centre; verify against the touch pad so the two HUDs don't fight.

**`scripts/spike/SpellPlaygroundController.gd`** — the biggest playground change:
- Replace every `Input.is_key_pressed(KEY_*)` (lines 189-197, 236-243) and the `match event.keycode` block (282-313) with named actions + `CastInput`. Debug-only keys (H/K/R/Tab/brackets) may stay raw **inside a `_debug_input` function that is clearly marked spike-only**, or move to a small debug action set — but movement, jump, duck, dash, parry, punch and cast must be action-based.
- Q/E spell cycling → **deleted**. Four slots, four buttons.
- Add a `GRIMOIRE` overlay (reuse `scripts/ui/Grimoire.gd` if it exists by then, else a Label list) so all 24 spells stay reviewable — but via the shipping selection UX, not via mid-combat cycling.
- `_cast()` uses `CastInput.placed_point(...)` instead of `get_global_mouse_position()`.

**`scenes/spike/SpellPlayground.tscn`** — add a `TouchControls` node with `force_visible = true` so the maker sees and uses the real pad on desktop at F5.

### 5.4 Explicitly NOT in this change

Balance re-tuning of the 24 spells beyond what the §4.4 audit forces; the progression/unlock *content* (which spell unlocks when — this spec only builds the gate); co-op replication of the new HUD; enemy AI aiming (unchanged, and still allowed to aim at the hero); a 5th slot.

---

## 6. Verification

### 6.1 New headless suite — `godot-project/tools/slice_test_castinput.gd`

Follows the existing `tools/slice*_test_*.gd` shape (prints `... tests: all PASS`, non-zero exit on failure). Five groups:

1. **NO-AUTO-AIM INVARIANT (the important one).** Build a hero; set the aim source to a fixed direction; run `CastInput.aim_dir()` with **zero** enemies in the tree, then with **five** enemies scattered at ±15°, ±45°, ±90°; assert the returned vector is **bit-identical** in all six cases. Then assert `SpellCaster` receives `target_pos == origin + aim*reach` exactly. *This single test makes R2 a regression-protected property instead of a comment.*
2. **Shape-forgiveness audit.** For every spell in `SpellLibrary.build_all()`, compute `effective_half_width` and `effective_range` and assert the ±8° inequality (§4.4). Print a full table (24 rows) so a failure names the spell and the shortfall. Expect several failures on the first run — that table IS the balance to-do list.
3. **Slot mapping.** Every one of the 24 spells maps to exactly one `SlotKind`; every class's `default_loadout` has exactly 4 entries, one per slot, all non-null; `resolve()` on a garbage id falls back cleanly.
4. **Touch/keyboard parity.** Drive a hero one physics frame with `Input.action_press("slot_2")`, then again with the keyboard binding, and assert identical spawned-spectacle count and position. Proves the single seam.
5. **The jump fix.** Assert `TouchControls`' jump button presses the `jump` action (a direct regression test for §1.2 defect 1).

### 6.2 Regression

- Full sweep: every `godot-project/tools/slice*_test_*.gd` (43 suites) stays green.
- `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project scenes/Main.tscn --quit-after 180` boots clean.
- `tools/slice_test_touch.gd` updated for the new button set and stays green.

### 6.3 Visual (Claude's eyes, GUI binary)

- Extend `tools/touch_capture.gd` to render the 4-slot pad with cooldown rings and the placement preview mid-drag; PNGs land in `%APPDATA%\Godot\app_userdata\Legacy Frontier\`.
- Extend `tools/spell_playground_capture.gd` with a per-slot shot.
- The verify loop for anything visual is **render a PNG and look at it**, per the standing note at `.superpowers/sdd/progress.md:9`.

### 6.4 What only the maker can verify (F5, `scenes/spike/SpellPlayground.tscn`)

Four buttons + direction aim under pressure; whether the joystick double-tap-flick dash misfires (§3.2 fallback); whether ±8° forgiveness feels right or whether widened beams now feel cheap; whether losing the cursor for placed spells feels worse on desktop than the clamped-cursor design predicts.

---

## 7. Rollout order

| phase | contents | risk |
|---|---|---|
| **A — playground** | `CastInput.gd` + `SpellSlots.gd` + the 4 new actions + playground moved onto actions + `TouchControls` in the playground with `force_visible` + a temporary in-playground grimoire. **Nothing in `scripts/combat/` behaviour changes.** Maker F5s the model itself. | none to the game |
| **B — the audit** | Run the §4.4 shape audit, publish the 24-row table, widen/shorten the failures with the maker. | balance only |
| **C — Hero** | Migrate `Hero.gd` to the 4-slot loop, delete the `Targeting` aim path, `ability_hud_state` → 4, `AbilityBar` layout, `TouchControls` cooldown rings + jump fix. | real; gated on A being felt-good |
| **D — the grimoire** | `Grimoire.gd`/`.tscn`, hub Armory entry point, `GameState.spell_loadout` persistence, class/rank gating. | contained |

Phase A is the whole point: the maker gets to *feel* the model in the thing they already F5 before a line of `Hero.gd` moves.

---

## 8. Open questions for the maker

1. **Cap = 4?** (Recommend yes. 3 + a dash button is the fallback if the flick-dash misfires.)
2. **Dash on the joystick double-tap-flick, or keep a dash button?** (Recommend the flick — it is what buys the button-count reduction, and dash direction already comes from the movement thumb.)
3. **Melee: arc-only, no target-seek?** (Recommend yes for R2 consistency; it will change how punching feels and may need a wider arc.)
4. **±8° forgiveness — right number?** (It is a `Tuning` knob; the audit table will show what it costs each of the 24 spells.)
5. **`frostpiercer`-class needles:** widen them, or shorten them, or accept that a few spells are deliberately precision tools that are simply harder on a phone? (Recommend widen — "harder on a phone" is exactly what mobile-first forbids.)
