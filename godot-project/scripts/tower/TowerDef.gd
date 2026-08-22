class_name TowerDef
extends Resource
## A whole tower: an ordered spine of typed floors + a default environment.
## Authored as a .tres (data/towers/*.tres). A new tower = a new file, no code.

@export var id: String = "ashspire"
@export var display_name: String = "The Ashen Tower"
@export var theme: EnvTheme = null            # default theme for floors that don't override
@export var floors: Array[FloorDef] = []      # ordered; floors.size() == the floor count
