extends Node
## Autoload "Tuning" — exposes the live-tunable feel Resource. Read sites use a
## null-safe helper so the code default always wins if the .tres or a field is
## missing (keeps headless tests + a fresh checkout on the committed defaults).

const CONFIG_PATH: String = "res://data/tuning.tres"

var cfg: TuningConfig


func _ready() -> void:
	cfg = load(CONFIG_PATH) as TuningConfig
	if cfg == null:
		cfg = TuningConfig.new()   # code defaults if the .tres is absent
