class_name TuningConfig
extends Resource
## Single live-tunable feel surface for the highest-traffic "how heavy does it
## feel" knobs. Edit res://data/tuning.tres in the inspector, or drag these in
## Remote -> Tuning while the game runs, to tune WITHOUT a relaunch.
##
## Only hero-local movement/feel constants live here (the ones the maker re-touches
## every session). Per-class ability tuning stays in Hero.CLASS_CONFIG; the long
## tail of colours/particles/anim constants stays as `const` in its owning script.
## Any field left unset falls back to the code default at the read site, so a
## missing/renamed field never crashes.

@export_group("Hero movement")
@export var hero_speed: float = 210.0    # base walk speed
@export var dash_speed: float = 620.0    # dash burst velocity (distance = speed*time)
@export var dash_time: float = 0.14      # dash duration AND i-frame window length

@export_group("Hero feel")
@export var hurt_hit_stop: float = 0.05  # freeze when the hero takes a hit
@export var hurt_shake: float = 7.0      # shake when the hero takes a hit
@export var melee_hit_stop: float = 0.07 # freeze when a melee connects
