class_name EnvTheme
extends Resource
## A tower/floor environment identity. Thin now (a wash tint over the primitive
## art); grows later (backdrop, music, hazard props) without touching consumers.

@export var name: String = "surface"
@export var wash_tint: Color = Color(0.20, 0.28, 0.22)
