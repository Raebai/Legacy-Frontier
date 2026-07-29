# A beam-shaped reactant for tools/beam_clash_probe.gd, duck-typed to the
# SpellReactor participant contract and — like every real spectacle — PARKED AT
# THE ORIGIN with its geometry living somewhere else entirely.
#
# Separate file rather than an inner class because the probe hands it to
# `load()`: an inner class of a `--script` SceneTree cannot be instanced by path.
extends Node2D

var shape: Dictionary = {}
var active: bool = true
var element: int = 0
var owner_node: Node = null
var consumed: int = 0
var frozen: int = 0


func reaction_shape() -> Dictionary:
	return shape


func reaction_active() -> bool:
	return active


func reaction_element() -> int:
	return element


func reaction_form() -> int:
	return ReactionTable.Form.BEAM


func reaction_owner() -> Node:
	return owner_node


func reaction_consume() -> void:
	consumed += 1


func reaction_freeze() -> void:
	frozen += 1


func reaction_release() -> void:
	frozen -= 1
