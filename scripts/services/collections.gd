extends Node
## Inventory and discovery facade. This service listens to the bus, not the player.
const Store = preload("res://scripts/core/save_store.gd")
var store = Store.new()
var discovered: Array = []
var story_id := ""
var persistent := true
var catalog: Dictionary = {}
func _ready() -> void:
	EventBus.unlock_requested.connect(unlock)
	EventBus.ending_reached.connect(func(_id: String, entry: String):
		if not entry.is_empty(): unlock(entry))
func configure(bundle: Dictionary, persistence: bool = true) -> void:
	catalog = bundle.catalog.duplicate(true)
	story_id = bundle.id
	persistent = persistence
	discovered.clear()
	if persistent:
		var data = store.read("collections").get("data", {}).get(story_id, [])
		if data is Array:
			for id in data:
				if catalog.entries.has(id) and not discovered.has(id): discovered.append(id)
		var endings = store.read("endings").get("data", {}).get(story_id, [])
		if endings is Array:
			for id in endings: unlock("ending_" + str(id))
func unlock(id: String) -> void:
	if not catalog.get("entries", {}).has(id) or discovered.has(id): return
	discovered.append(id)
	if persistent:
		var profile: Dictionary = store.read("collections").get("data", {})
		profile[story_id] = discovered.duplicate()
		var error: String = store.write("collections", profile)
		if not error.is_empty(): EventBus.notification.emit(error)
	EventBus.custom_event.emit("collection_unlocked", {"id": id})
func add_item(id: String, count: int = 1) -> String:
	if count <= 0: return "数量必须为正整数"
	return GameState.apply({"inventory": {id: count}})
func remove_item(id: String, count: int = 1) -> String:
	if count <= 0: return "数量必须为正整数"
	return GameState.apply({"inventory": {id: -count}})
func use_item(id: String) -> String:
	if GameState.inventory.get(id, 0) < 1 or not catalog.items.has(id): return "背包中没有该道具"
	var item: Dictionary = catalog.items[id]
	if not item.get("usable", false): return "这件道具需要在剧情中使用"
	var effects: Dictionary = item.get("effects", {}).duplicate(true)
	if item.get("consume", false):
		var delta: Dictionary = effects.get("inventory", {})
		delta[id] = delta.get(id, 0) - 1
		effects["inventory"] = delta
	if item.has("use_unlock"):
		var entries: Array = effects.get("unlock", [])
		entries.append(item.use_unlock)
		effects["unlock"] = entries
	var error := GameState.apply(effects)
	if error.is_empty(): EventBus.notification.emit("已使用：" + Localization.text(item.name))
	return error
