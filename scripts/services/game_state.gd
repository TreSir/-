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
	EventBus.game_started.emit()
	EventBus.flags_changed.emit()
	EventBus.inventory_changed.emit()

func validate_snapshot(snapshot: Dictionary, defs: Variant = null, items: Variant = null) -> String:
	if defs == null: defs = definitions
	if items == null: items = catalog
	if not snapshot.get("flags") is Dictionary or not snapshot.get("inventory") is Dictionary: return "状态快照格式错误"
	for id in snapshot.flags:
		if not defs.has(id): return "存档有未声明 Flag：" + str(id)
		var error: String = Rules.value_error(snapshot.flags[id], defs[id])
		if not error.is_empty(): return str(id) + "：" + error
	for id in snapshot.inventory:
		if not items.get("items", {}).has(id): return "存档有未知道具：" + str(id)
		var count: Variant = snapshot.inventory[id]
		if not Rules.integer(count) or count <= 0 or count > items.items[id].get("max_stack", 99): return "非法道具数量：" + str(id)
	return ""

func snapshot() -> Dictionary:
	return {"flags": flags.duplicate(true), "inventory": inventory.duplicate(true)}

func restore(snapshot: Dictionary) -> String:
	var error := validate_snapshot(snapshot)
	if not error.is_empty(): return error
	flags = defaults()
	flags.merge(snapshot.flags, true)
	inventory = snapshot.inventory.duplicate(true)
	EventBus.flags_changed.emit()
	EventBus.inventory_changed.emit()
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
	for id in effects.get("inventory", {}):
		if effects.inventory[id] > 0:
			var item: Dictionary = catalog.items[id]
			if item.has("entry"): EventBus.unlock_requested.emit(item.entry)
	for id in effects.get("unlock", []): EventBus.unlock_requested.emit(id)
	return ""
