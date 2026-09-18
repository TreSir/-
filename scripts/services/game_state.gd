extends Node
const Rules = preload("res://scripts/core/rules.gd")
var definitions: Dictionary = {}
var catalog: Dictionary = {}
var flags: Dictionary = {}
var inventory: Dictionary = {}

func configure(bundle: Dictionary) -> void:
	definitions = bundle.flags.duplicate(true)
	catalog = bundle.catalog.duplicate(true)

func defaults() -> Dictionary:
	var result: Dictionary = {}
	for id in definitions: result[id] = definitions[id]["default"]
	return result

func reset() -> void:
	flags = defaults()
	inventory.clear()

func validate_snapshot(snapshot: Dictionary, defs: Variant = null, items: Variant = null) -> String:
	if defs == null: defs = definitions
	if items == null: items = catalog
	# 体检标准在 Rules 里：save_manager 也要用同一份，而它不碰 GameState。
	return Rules.snapshot_error(snapshot, defs, items)

func snapshot() -> Dictionary:
	return {"flags": flags.duplicate(true), "inventory": inventory.duplicate(true)}

func restore(snapshot: Dictionary) -> String:
	var error := validate_snapshot(snapshot)
	if not error.is_empty(): return error
	flags = defaults()
	flags.merge(snapshot.flags, true)
	inventory = snapshot.inventory.duplicate(true)
	return ""

func apply(effects: Dictionary) -> String:
	var error: String = Rules.effects_error(effects, definitions, catalog)
	if not error.is_empty(): return error
	var candidate := snapshot()
	candidate.flags.merge(effects.get("set", {}), true)
	for id in effects.get("add", {}): candidate.flags[id] += effects.add[id]
	for id in effects.get("inventory", {}):
		candidate.inventory[id] = candidate.inventory.get(id, 0) + effects.inventory[id]
		if candidate.inventory[id] == 0: candidate.inventory.erase(id)
	error = validate_snapshot(candidate)
	if not error.is_empty(): return error
	restore(candidate)
	return ""
