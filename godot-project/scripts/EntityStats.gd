class_name EntityStats
extends Resource

# ---- identity tags (mostly fixed) ----------------------------------------
@export var race: String = ""
@export var character_class: String = ""  # `class` is reserved-ish; use character_class
@export var traits: Array[String] = []

# ---- combat stats (used from Tier 1.5+ — currently passive) --------------
@export var max_hp: int = 100
@export var current_hp: int = 100

# ---- behavioural state (used in dialogue from v0.5+ — currently passive) -
@export_range(-1.0, 1.0, 0.05) var mood: float = 0.0       # -1 sad / hostile  ..  1 happy / open
@export_range(-1.0, 1.0, 0.05) var trust: float = 0.0      # -1 hostile-toward-player  ..  1 trusting
@export_range(0.0, 1.0, 0.05) var patience: float = 1.0    # 0 done / will-leave  ..  1 fresh
