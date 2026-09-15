extends Node
## Engine-independent gameplay API; can be called by StoryRunner or Dialogic.
signal changed
signal notice(message: String)
signal item_used(effects: Dictionary)
const SaveStore = preload("res://scripts/core/save_store.gd")

var catalog: Dictionary = {}
var inventory: Dictionary = {}
var discovered: Array = []
var story_id := ""
var persist_collection := true
var store = SaveStore.new()

func setup(id: String, persistent: bool = true) -> String:
	var file := FileAccess.open("res://data/catalog.json", FileAccess.READ)
	if file == null: return "无法读取道具与图鉴配置。"
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.get("items") is Dictionary or not data.get("entries") is Dictionary:
		return "道具与图鉴配置格式错误。"
	for key in data.items:
		var item: Variant = data.items[key]
		if not item is Dictionary or not item.get("name") is String: return "无效道具：" + key
		var cap: Variant = item.get("max_stack", 99)
		if not (cap is int or cap is float) or cap < 1 or cap != floor(cap): return "无效堆叠上限：" + key
		for field in ["entry", "use_unlock"]:
			if item.has(field) and not data.entries.has(item[field]): return "未知图鉴引用：" + key
	for key in data.entries:
		if not data.entries[key] is Dictionary or not data.entries[key].get("name") is String:
			return "无效图鉴：" + key
	catalog = data
	story_id = id
	persist_collection = persistent
	discovered.clear()
	if persistent:
		var saved: Variant = store.read("collections").get("data", {}).get(id, [])
		if saved is Array:
			for entry in saved:
				if catalog.entries.has(entry) and not discovered.has(entry): discovered.append(entry)
	reset_inventory()
	return ""

func reset_inventory() -> void:
	inventory.clear()
	changed.emit()

func count(id: String) -> int:
	return int(inventory.get(id, 0))

func has_item(id: String, amount: int = 1) -> bool:
	return amount > 0 and count(id) >= amount

func add_item(id: String, amount: int = 1) -> bool:
	if amount <= 0 or not catalog.items.has(id): return false
	var item: Dictionary = catalog.items[id]
	if count(id) + amount > int(item.get("max_stack", 99)):
		notice.emit("道具数量已达上限：" + str(item.name))
		return false
	inventory[id] = count(id) + amount
	if item.has("entry"): unlock_entry(item.entry)
	changed.emit()
	notice.emit("获得 %s × %d" % [item.name, amount])
	return true

func remove_item(id: String, amount: int = 1) -> bool:
	if not has_item(id, amount): return false
	inventory[id] = count(id) - amount
	if inventory[id] == 0: inventory.erase(id)
	changed.emit()
	return true

func use_item(id: String) -> bool:
	if not has_item(id) or not catalog.items.has(id): return false
	var item: Dictionary = catalog.items[id]
	if not item.get("usable", false):
		notice.emit("这件道具需要在剧情中使用。")
		return false
	if item.get("consume", false): remove_item(id)
	if item.has("use_unlock"): unlock_entry(item.use_unlock)
	item_used.emit(item.get("effects", {}).duplicate(true))
	changed.emit()
	notice.emit("已使用：" + str(item.name))
	return true

func unlock_entry(id: String) -> bool:
	if not catalog.entries.has(id): return false
	if discovered.has(id): return true
	discovered.append(id)
	if persist_collection:
		var profile: Dictionary = store.read("collections").get("data", {})
		profile[story_id] = discovered.duplicate()
		var error: String = store.write("collections", profile)
		if not error.is_empty(): notice.emit(error)
	changed.emit()
	return true

func validate_inventory(data: Variant) -> String:
	if not data is Dictionary: return "背包存档格式错误。"
	for id in data:
		var amount: Variant = data[id]
		if not catalog.items.has(id): return "存档包含未知道具：" + str(id)
		if not (amount is int or amount is float): return "无效道具数量。"
		if amount < 1 or amount != floor(amount) or amount > catalog.items[id].get("max_stack", 99):
			return "道具数量超出范围：" + str(id)
	return ""

func restore_inventory(data: Dictionary) -> void:
	inventory = data.duplicate(true)
	for id in inventory:
		var item: Dictionary = catalog.items[id]
		if item.has("entry"): unlock_entry(item.entry)
	changed.emit()
