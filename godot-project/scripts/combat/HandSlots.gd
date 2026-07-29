class_name HandSlots
extends RefCounted
## WHAT YOU ARE CURRENTLY HOLDING — the model behind the two-button control
## scheme and the League-style slot bar along the bottom of the screen.
##
## THE SCHEME (maker-set, and the reason this class exists):
##   LEFT CLICK  = use whatever is selected — punch with empty hands, drag the
##                 blade with a weapon, cast with a spell.
##   RIGHT CLICK = DEFLECT. Always, in every state, armed or not.
##   SCROLL      = move along the slots.
## Two buttons total is what makes it work on a phone: one contextual "use" and
## one universal defence, instead of a key per ability. Everything else in this
## file exists to make that single "use" button unambiguous.
##
## Weapons and spells share ONE carousel deliberately. They are alternatives —
## you are punching, or swinging, or casting — so a single selection answers
## "what does left click do right now" with no modes and nothing hidden.
##
## Pure data: no nodes, no drawing, no input polling. The bar renders it, the
## controller drives it, and it stays headless-testable.

enum Kind { FISTS, WEAPON, SPELL }

## The carousel. Index 0 is always FISTS so a player can never end up with no
## melee option at all, which would strand them if every spell were on cooldown.
var slots: Array[Dictionary] = []
var selected: int = 0

## A CONTEXTUAL CLAIM on the use button, published from outside once the world
## says something nearer-to-hand than the carousel should answer the press.
## Empty string = no claim, the selected slot decides as normal.
##
## Today the only claimant is the ROCK WALL TWO-BEAT: the first press summons the
## wall, the second press has to be the PUNCH that sends it — one button, two
## beats — even though what is held is still a spell. That exception lives here
## rather than in the input handler so `primary_action()` remains the single
## answer to "what does the use button do right now"; a controller that branched
## on the wall itself before asking would be a second, competing answer, and the
## two would drift.
##
## Deliberately a plain string set from outside: this class stays pure data with
## no tree access, so the world query (is there a wall of mine in reach, am I
## facing it, is the combo window still open) stays in the caster where the feel
## numbers live, and this file stays headless-testable.
var contextual_primary: String = ""


func _init() -> void:
	slots = [_fists()]


static func _fists() -> Dictionary:
	return {"kind": Kind.FISTS, "id": "fists", "name": "Fists", "cooldown": 0.0, "ready": true}


## Rebuild from a weapon id list and a spell list. Called when a loadout changes.
## Order is fists, then weapons, then spells: melee lives at the near end of the
## carousel because it is the panic option you want to reach quickly.
func rebuild(weapons: Array, spells: Array) -> void:
	slots = [_fists()]
	for w: String in weapons:
		slots.append({"kind": Kind.WEAPON, "id": w, "name": w.capitalize(),
			"cooldown": 0.0, "ready": true})
	for s in spells:
		if s == null:
			continue
		slots.append({"kind": Kind.SPELL, "id": String(s.get("id")),
			"name": String(s.get("display_name")), "cooldown": 0.0, "ready": true,
			"spell": s})
	selected = clampi(selected, 0, slots.size() - 1)


## Move along the carousel. Wraps, because a scroll wheel that dead-ends feels
## broken and there is no visual end to the bar.
func cycle(dir: int) -> void:
	if slots.is_empty():
		return
	selected = wrapi(selected + signi(dir), 0, slots.size())


func select(index: int) -> void:
	if slots.is_empty():
		return
	selected = clampi(index, 0, slots.size() - 1)


func current() -> Dictionary:
	if slots.is_empty() or selected < 0 or selected >= slots.size():
		return _fists()
	return slots[selected]


func current_kind() -> int:
	return int(current().get("kind", Kind.FISTS))


## Hand the use button to the world for a beat (or give it back with ""). Called
## every frame by whoever owns the world query — passing the same value twice is
## free, so the caller never has to track edges.
func claim_primary(action: String) -> void:
	contextual_primary = action


## True while something in the world has taken the use button off the carousel.
## The HUD/tell asks this; it must never have to re-derive the rule.
func has_contextual_primary() -> bool:
	return contextual_primary != ""


## What LEFT CLICK means right now. The whole point of the model in one call.
## A contextual claim wins over the carousel — that is what makes it a claim —
## and it never touches `selected`, so the bar keeps showing what you actually
## hold and the press after the claim lapses is a normal cast again.
func primary_action() -> String:
	if contextual_primary != "":
		return contextual_primary
	match current_kind():
		Kind.WEAPON:
			return "swing"
		Kind.SPELL:
			return "cast"
	return "punch"


## The equipped weapon id, or "" when unarmed. Drives which blade the rig draws.
func weapon_id() -> String:
	var c: Dictionary = current()
	return String(c.get("id", "")) if int(c.get("kind", Kind.FISTS)) == Kind.WEAPON else ""


## The selected SpellDef, or null. Null means left click must not try to cast.
func spell() -> Variant:
	var c: Dictionary = current()
	return c.get("spell") if int(c.get("kind", Kind.FISTS)) == Kind.SPELL else null


# ---- cooldowns (the bar draws these as the League-style sweep) --------------

func start_cooldown(index: int, seconds: float) -> void:
	if index < 0 or index >= slots.size():
		return
	slots[index]["cooldown"] = seconds
	slots[index]["ready"] = seconds <= 0.0


func tick(delta: float) -> void:
	for s: Dictionary in slots:
		if float(s.get("cooldown", 0.0)) > 0.0:
			s["cooldown"] = maxf(float(s["cooldown"]) - delta, 0.0)
			s["ready"] = float(s["cooldown"]) <= 0.0


## A slot on cooldown is still SELECTABLE — you can scroll onto it and see the
## sweep. It just refuses to fire. Blocking selection would make the bar lie
## about what you own.
func is_ready(index: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
	return bool(slots[index].get("ready", true))


func current_ready() -> bool:
	return is_ready(selected)
