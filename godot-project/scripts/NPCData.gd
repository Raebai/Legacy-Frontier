class_name NPCData
extends Resource
## A TOWNSPERSON, as data. Name, colour, and the handful of things they say.
##
## ⚠ THIS USED TO BE THE LLM STACK'S IDENTITY RESOURCE and it is deliberately not
## that any more. It carried `personality_prompt`, `tier`, `patience_decay_rate`,
## `interest_keywords`, `initial_relationships` and an `EntityStats` sub-resource,
## all of which existed to feed a local Ollama server at `127.0.0.1:11434` and a
## four-layer memory file under `user://npc_memory/`. On a phone that address is
## the phone's own loopback, so none of it could ever have run on the target
## platform, and the design doc cuts persistent world / NPC memory / LLM anything
## permanently. It is all in git history; nothing here reaches for any of it.
##
## What replaces it is `Bark` — one line over a head, then gone. A townsperson
## says one of `lines` when you walk up and press interact, in the
## chalk-and-graphite voice, and that is the entire conversation system.

## Stable id. Used to place the body in the town and to seed its voice, so the
## same person sounds like themselves every launch.
@export var npc_id: String = ""

## Shown on the walk-up hint: "[E] <name>".
@export var npc_name: String = "Someone"

## Tint of the stick figure.
@export var display_color: Color = Color(0.95, 0.5, 0.2, 1.0)

## WHAT THEY SAY. One is picked per interaction, never twice in a row while there
## is more than one to choose from.
##
## Same hard rules as `Bark.LINES`, because these land in the same bubble: five
## words or fewer, present tense, no proper nouns, never a question the player is
## expected to answer, never an instruction (that is the station hints' job).
@export var lines: Array[String] = []
