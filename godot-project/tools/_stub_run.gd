extends Node
## Stand-in for the `GameState` autoload inside a `--script` capture, which registers
## no autoloads at all. Carries the one field `RunSummary` reads.
var last_run: Dictionary = {}
