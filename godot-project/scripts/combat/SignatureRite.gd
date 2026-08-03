class_name SignatureRite
extends RefCounted
## THE SIGNATURE RITE — DECLARE / CHARGE / RELEASE.
##
## The reusable ceremony every signature ult is framed by. It is a FRAMEWORK and
## not a move: it owns no damage, no geometry and no spell, it just dresses the
## windup that `Hero._begin_summon` / `Hero._begin_channel` already hold. Any
## caster that commits its body for a beat before a spell exists — the hero today,
## a boss or the playground rig tomorrow — calls the same two functions and gets
## the same beat, which is the whole reason this is not written inside Hero.gd.
##
## ⚠ THE ONE RULE THAT MAKES IT FREE: **the rite adds no time.** Every beat below
## is a FRACTION of a windup that is already being spent. A 0.42 s summon plus a
## 0.9 s declare would be a 1.3 s ult, and forty of those in a climb is a tax, not
## a ceremony. So the framework never lengthens a cast — if a declare feels rushed
## the honest fix is a longer WINDUP on that spell (which is a real balance change,
## paid for in dodge window), never a longer card.
##
## THE THREE BEATS, and what each is FOR:
##
##   DECLARE  first 30% of the windup, capped at 0.45 s. The name card fades in and
##            the world dims. This is the announcement — the attacker's moment.
##   CHARGE   the middle, and **THIS IS THE OPPONENT'S DODGE WINDOW.** Nothing else
##            happens during it, deliberately: the sigil grows, the motes converge,
##            and the person being cast at has a legible, uninterrupted span in
##            which to leave, close, or break the cast. `dodge_window()` returns
##            exactly this number so a balance argument can be had about it.
##   RELEASE  last 8%. The card clears just before the spectacle exists, so the
##            name is off screen by the time the thing it named arrives.
##
## THREE SUPPRESSION RULES, all load-bearing (see `should_declare`). Declare
## fatigue is the number-one risk to this whole idea: ceremony that plays on every
## press stops reading as ceremony inside one floor.
##
## ⚠ HEADLESS SAFETY. Everything here is either pure maths or a Node method.
## No static function in this file may NAME an autoload (`Sfx`, `Juice`, `Tuning`
## …): autoloads are not registered under `--script`, and naming one in a STATIC
## context is a *compile* error that fails the entire dependency chain with a
## misleading message. Where a sound is wanted it is fetched with
## `Engine.get_main_loop()` -> `get_node_or_null(^"/root/Sfx")`, the same idiom
## `SpellDeflect` uses.

## --- THE WINDUP LADDER ------------------------------------------------------
## Multiplier on `CastStyle.duration(pose)`, indexed by `SpellTier.Tier`
## (QUICK, HEAVY, ULT). This table used to live in Hero as CAST_TIER_WINDUP; it is
## here now because the windup IS the rite — the framework cannot report an
## opponent's dodge budget from a number a single caster owns privately. Hero
## reads it back through `windup_for()`, so there is one table, not two.
##
## A jab is nearly instant; an ult is a visible, punishable commitment. UNTESTED
## FEEL GUESS, but the DIRECTION is a locked rule: longer cast = more power = more
## counterplay, never less.
const TIER_WINDUP: Array[float] = [0.35, 1.0, 1.9]

## Fraction of the windup spent announcing, and the hard ceiling on it. The cap is
## what stops a 2.6 s domain cast from holding a name card for three-quarters of a
## second — past ~0.45 s a card stops reading as an announcement and starts
## reading as a loading screen.
const DECLARE_FRACTION: float = 0.30
const DECLARE_MAX: float = 0.45
## Fraction of the windup spent clearing the card before the spectacle spawns.
const RELEASE_FRACTION: float = 0.08

## Card fade timings. Far faster than `Boss._play_intro`'s 0.5 / 1.4 / 0.5 — a boss
## intro is a scene, a signature is an attack, and the whole rite has to fit inside
## a windup as short as 0.42 s.
const CARD_FADE_IN: float = 0.10
const CARD_FADE_OUT: float = 0.15

## How long the SAME signature stays "already introduced". You announce your sword
## once; you do not re-introduce yourself every eight seconds. This is the single
## most likely number in the file to need tuning, and the failure signal in a
## playtest is specific — the maker starts saying "get on with it". Tune THIS up
## before touching the card's timing: a card that flashes too fast is worse than
## no card at all.
const REPEAT_WINDOW: float = 12.0

## How dark the world goes behind the card. A DIM, not a desaturation: a true
## saturation drain belongs in `PostProcess` (which owns the screen grade and is
## not this file's to change), and a self-contained overlay is the version that
## cannot leave the arena tinted when a cast is interrupted mid-declare.
const DIM_ALPHA: float = 0.16

## Card presentation. Smaller than the boss card's 36 and lower on the screen at
## 96 rather than 120: the boss is the bigger event and the hierarchy has to hold,
## or a signature reads as more important than the thing that is trying to kill you.
const CARD_FONT_SIZE: int = 28
const CARD_TOP: float = 96.0
const CARD_OUTLINE: int = 7
const CARD_OUTLINE_COLOR: Color = Color(0.05, 0.02, 0.03, 0.95)
## Above the ability bar and the world, below a pause menu.
const CARD_LAYER: int = 90
## Node name the card is added under, so `dismiss()` can find exactly one.
const CARD_NAME: StringName = &"SignatureRiteCard"

enum Beat { DECLARE, CHARGE, RELEASE }

## How many cards are on screen right now, across every caster. Co-op: two heroes
## ulting on the same frame must not stack two labels over each other — the second
## one's sigil and dim still play, only the text is suppressed. Static because the
## SCREEN is the shared resource, not any one hero.
static var _cards_open: int = 0


# ------------------------------------------------------------------ the ladder

## The windup a spell commits its caster to, in seconds — the single source both
## the caster and the rite read.
##
## A channelled spell's `cast_time` is used VERBATIM and never scaled by the tier
## table on top: that number is already the authored, balance-tuned dodge window,
## and multiplying it again would silently retune every channelled spell in the
## game. Everything else derives from its body language (`CastStyle`) scaled by
## what it costs (`SpellTier`).
static func windup_for(spell: SpellDef) -> float:
	if spell == null:
		return 0.0
	if spell.cast_time > 0.0:
		return spell.cast_time
	var pose: int = CastStyle.for_spell_def(spell)
	var tier: int = clampi(SpellTier.of(spell), 0, TIER_WINDUP.size() - 1)
	# The 0.02 floor is a guard, not a feel number: a zero-length windup would make
	# the spawn ungated and turn a "process" back into an instant spawn.
	return maxf(CastStyle.duration(pose) * TIER_WINDUP[tier], 0.02)


# ------------------------------------------------------------------- the beats

## Seconds of DECLARE inside `windup`.
static func declare_time(windup: float) -> float:
	return minf(maxf(windup, 0.0) * DECLARE_FRACTION, DECLARE_MAX)


## Seconds of RELEASE inside `windup`.
static func release_time(windup: float) -> float:
	return maxf(windup, 0.0) * RELEASE_FRACTION


## Seconds of CHARGE inside `windup` — whatever the announcement and the clear did
## not take. Clamped at zero so a pathologically short windup degrades to "all
## declare, no charge" rather than reporting a negative span.
static func charge_time(windup: float) -> float:
	return maxf(maxf(windup, 0.0) - declare_time(windup) - release_time(windup), 0.0)


## **THE OPPONENT'S DODGE BUDGET, in seconds.** Named and exported precisely so it
## can be argued about: it is the span in which the caster is committed, visible,
## and doing nothing but charging, and it is what an opponent actually gets to
## spend on leaving, closing or breaking the cast.
##
## It is deliberately the CHARGE and not the whole windup. The declare beat is
## announcement — a competent opponent is already reacting during it — but the
## charge is the part that is guaranteed to be uninterrupted by the game's own
## presentation, so it is the honest floor on the read.
##
## At `SPEED` 210 px/s a body covers `210 * dodge_window` px: ~55 px on a planted
## 0.42 s signature (one dash clears most footprints), ~170 px on a 1.0 s channel,
## ~215 px on a 1.25 s one. A signature ult needs the LONGEST tell, never an
## exemption from having one.
static func dodge_window(windup: float) -> float:
	return charge_time(windup)


## Which beat a cast is in, `elapsed` seconds into a `windup`-long commitment.
static func beat_at(windup: float, elapsed: float) -> int:
	var d: float = declare_time(windup)
	if elapsed < d:
		return Beat.DECLARE
	if elapsed < maxf(windup, 0.0) - release_time(windup):
		return Beat.CHARGE
	return Beat.RELEASE


# ------------------------------------------------------- the suppression rules

## Should this cast get a name card? PURE, and takes its whole world as arguments,
## so all three rules are headless-testable rather than being discovered in a
## playtest.
##
## 1. NEVER on a QUICK cast. A quick signature is a mobility burst or a jab; a name
##    card on a blink is a name card nobody can read, and it makes the ults that
##    deserve one cheaper by association.
## 2. NEVER on a REPEAT inside `REPEAT_WINDOW`. See that constant.
## 3. NEVER while another card is on screen. Two stacked labels are unreadable, and
##    in co-op that is not an edge case, it is Tuesday.
##
## `last_declared` maps `spell.id` -> the timestamp it was last announced at. The
## caller owns that dictionary (Hero keeps one per hero) so two heroes never share
## a suppression clock — one player ulting must not silence the other's card.
static func should_declare(tier: int, spell_id: String, last_declared: Dictionary,
		now: float, card_live_now: bool) -> bool:
	if tier == SpellTier.Tier.QUICK:
		return false
	if card_live_now:
		return false
	if spell_id != "" and last_declared.has(spell_id):
		if now - float(last_declared[spell_id]) < REPEAT_WINDOW:
			return false
	return true


## Is a card on screen anywhere right now?
static func card_live() -> bool:
	return _cards_open > 0


# ------------------------------------------------------------------ the card

## Play the DECLARE beat for `host`: a name card at the top third plus a dim behind
## it, both timed to fit inside `windup` and both torn down by `dismiss()` if the
## cast dies early. Returns true if a card was actually raised.
##
## The card is parented to the HOST (as a CanvasLayer, so it still draws
## full-screen and ignores the hero's transform). That is what makes cleanup
## automatic: a hero who dies mid-declare takes their own card with them, and
## there is no global registry to leak.
##
## `text` is the spell's display name, upper-cased by the caller. No subtitle, no
## class name, no "ULTIMATE" chrome — the name is the whole point.
static func announce(host: Node, text: String, colour: Color, windup: float) -> bool:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return false
	if text.strip_edges() == "":
		return false
	dismiss(host)  # a caster can be interrupted, never queued — never stack two
	var card := Card.new()
	card.name = String(CARD_NAME)
	card.setup(text, colour, windup)
	host.add_child(card)
	_play_sfx("charge_up", -6.0, 0.05)
	return true


## Tear the card down NOW, without waiting out its timeline. Called on any
## interruption — a shattered channel, a cancelled summon, a co-op down — so a
## broken cast never leaves its own name hanging over the arena.
##
## Safe to call unconditionally; a host with no card is a no-op.
static func dismiss(host: Node) -> void:
	if host == null or not is_instance_valid(host):
		return
	var existing: Node = host.get_node_or_null(NodePath(String(CARD_NAME)))
	if existing != null:
		existing.queue_free()


## Sound without naming the autoload — see the headless-safety note in the header.
static func _play_sfx(key: String, volume_db: float, pitch: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sfx: Node = tree.root.get_node_or_null(^"/root/Sfx")
	if sfx != null and sfx.has_method(&"play"):
		sfx.call("play", key, volume_db, pitch)


## The card itself. Driven by an explicit clock in `_process` rather than a Tween
## on purpose: hitstop and the epic-moment freeze both move `Engine.time_scale`,
## and a rite that has to survive being frozen mid-declare is far easier to reason
## about as three explicit phases than as three chained tweens.
class Card:
	extends CanvasLayer

	var _label: Label = null
	var _dim: ColorRect = null
	var _total: float = 0.5
	var _elapsed: float = 0.0
	var _fade_out_at: float = 0.35

	func setup(text: String, colour: Color, windup: float) -> void:
		layer = SignatureRite.CARD_LAYER
		_total = maxf(windup, SignatureRite.CARD_FADE_IN + SignatureRite.CARD_FADE_OUT)
		# Clear the card just BEFORE the spectacle exists, so the name is gone by
		# the time the thing it named arrives on screen.
		_fade_out_at = maxf(_total - SignatureRite.release_time(windup)
			- SignatureRite.CARD_FADE_OUT, SignatureRite.CARD_FADE_IN)
		_dim = ColorRect.new()
		_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		_dim.color = Color(0.0, 0.0, 0.0, 0.0)
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_dim)
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_label.offset_top = SignatureRite.CARD_TOP
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.text = text
		# The card is tinted the SPELL's colour, never white: a declared signature
		# is then already class-legible before a single pixel of the spell exists.
		_label.add_theme_font_size_override(&"font_size", SignatureRite.CARD_FONT_SIZE)
		_label.add_theme_color_override(&"font_color",
			Color(colour.r, colour.g, colour.b, 1.0))
		_label.add_theme_constant_override(&"outline_size", SignatureRite.CARD_OUTLINE)
		_label.add_theme_color_override(&"font_outline_color",
			SignatureRite.CARD_OUTLINE_COLOR)
		_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		add_child(_label)

	func _enter_tree() -> void:
		SignatureRite._cards_open += 1

	func _exit_tree() -> void:
		# Decremented on EXIT rather than in a timeout, so an interrupted cast that
		# queue_free()s the card mid-declare still releases the screen. Clamped
		# because a double-exit would otherwise drive the counter negative and
		# permanently suppress every future card in the session.
		SignatureRite._cards_open = maxi(SignatureRite._cards_open - 1, 0)

	func _process(delta: float) -> void:
		_elapsed += delta
		var a: float = 0.0
		if _elapsed < SignatureRite.CARD_FADE_IN:
			a = _elapsed / SignatureRite.CARD_FADE_IN
		elif _elapsed < _fade_out_at:
			a = 1.0
		else:
			a = 1.0 - (_elapsed - _fade_out_at) / SignatureRite.CARD_FADE_OUT
		a = clampf(a, 0.0, 1.0)
		if _label != null:
			_label.modulate = Color(1.0, 1.0, 1.0, a)
		if _dim != null:
			_dim.color = Color(0.0, 0.0, 0.0, SignatureRite.DIM_ALPHA * a)
		if _elapsed >= _fade_out_at + SignatureRite.CARD_FADE_OUT:
			queue_free()
