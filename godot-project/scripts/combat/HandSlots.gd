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


## What LEFT CLICK means right now. The whole point of the model in one call.
func primary_action() -> String:
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
