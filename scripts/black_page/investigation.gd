extends Node
## Investigation orchestration; GameState remains the sole typed-state owner.
signal changed
const Loader = preload("res://scripts/black_page/data_loader.gd")
const Rules = preload("res://scripts/core/rules.gd")
const Store = preload("res://scripts/core/save_store.gd")
var bundle: Dictionary = {}
var journal: Array = []
var pending: Array = []
var active_action := ""
var ticket := 0
var directory := "res://data/black_page"

func open() -> String:
	var loader = Loader.new()
	var compiled: Dictionary = loader.compile(directory)
	if not loader.error.is_empty(): return loader.error
	bundle = compiled
	GameState.configure(bundle)
	new_game()
	return ""

func new_game() -> void:
	ticket += 1
	active_action = ""
	pending.clear()
	# 与序章结尾直接衔接：许妍凌晨那通电话断了之后，你没能再联系上她。
	# 这里不再提「林墨发来资料」——林墨在第一章里还没登场，资料也不是他送来的。
	journal = ["天亮了。雨没有停，只是比昨夜小了些。\n许妍的电话断掉之后，你再也没能联系上她。\n桌上的黑色笔记安静地放着。你还没有想清楚它到底是什么——但昨夜确实发生过。"]
	GameState.reset()
	changed.emit()

## 点亮一个侧栏入口。
##
## 为什么需要它：开场先要有一段剧情（手机震动 → 读到消息 → 自言自语），
## 剧情走完才该出现「案件」这些图标。而 `effects` 只在**行动**里跑，
## 开场这段不是行动，没有任何地方能写旗标——所以补这个口子。
## 界面调这个，不要越过游戏模块去直接改底层状态。
func reveal_ui(keys: Array) -> String:
	var patch := {}
	for key in keys:
		patch["ui." + str(key)] = true
	if patch.is_empty(): return ""
	var error: String = GameState.apply({"set": patch})
	if not error.is_empty(): return error
	changed.emit()
	return ""

## 剧情内容写状态的唯一入口。
##
## 序章那种脚本化段落不是「行动」，跑不到 complete_action 的事务里，但它同样
## **不能越过游戏模块直接改底层状态**——所以在这里开一个受校验的口子：
## 改完照常发 changed，界面/结算该刷新的都会刷新。
func apply_state(changes: Dictionary) -> String:
	if changes.is_empty(): return ""
	var error: String = GameState.apply({"set": changes})
	if not error.is_empty(): return error
	changed.emit()
	return ""

## 只读的旗标快照，给需要整份状态的调用方（例如小游戏初始化）用。
## 界面走这个，不要直接摸 GameState。
func flags_snapshot() -> Dictionary:
	return GameState.flags.duplicate(true)

func flag(id: String) -> Variant: return GameState.flags.get(id)
func owns(id: String) -> bool: return GameState.inventory.get(id, 0) > 0
func matches(conditions: Array) -> bool: return Rules.matches(conditions, GameState.flags, GameState.inventory)
func person_flag(id: String, field: String) -> Variant: return flag("person." + id + "." + field)
func person_name(id: String) -> String:
	return bundle.people[id].real_name if person_flag(id, "identity") == 100 else bundle.people[id].name

func available(id: String) -> bool:
	if not bundle.actions.has(id) or flag("ending") != "": return false
	return not flag("action." + id + ".done") and matches(bundle.actions[id].get("requires", []))

func begin_action(id: String) -> String:
	if not active_action.is_empty(): return "请先结束当前调查。"
	if not available(id): return "这条调查方向已经不可用。"
	if flag("actions_left") <= 0: return "今天已经没有调查行动。"
	active_action = id
	ticket += 1
	return ""

func cancel_action() -> void:
	active_action = ""
	ticket += 1

func complete_action(token: int, result: Dictionary = {}) -> String:
	if token != ticket or active_action.is_empty(): return "调查回调已过期。"
	var id := active_action
	var action: Dictionary = bundle.actions[id]
	if action.kind == "minigame" and result.get("success") != true: return "尚未完成还原；可以重试或返回。"
	if not available(id): return "调查方向发生变化，请返回。"
	var candidate := GameState.snapshot()
	var gained: Array = []
	for clue in action.clues:
		if not candidate.inventory.has(clue):
			candidate.inventory[clue] = 1
			_apply(candidate, bundle.clues[clue].get("effects", {}))
			gained.append(bundle.clues[clue].name)
	_apply(candidate, action.get("effects", {}))
	candidate.flags["action." + id + ".done"] = true
	candidate.flags.actions_left -= 1
	var error: String = GameState.validate_snapshot(candidate)
	if not error.is_empty(): return error
	GameState.restore(candidate)
	cancel_action()
	_log(action.text + ("\n获得线索：" + "、".join(gained) if not gained.is_empty() else ""))
	EventBus.custom_event.emit("investigation_completed", {"id": id, "clues": action.clues.duplicate()})
	if flag("actions_left") == 0:
		error = end_day()
		if not error.is_empty(): _log(error)
	changed.emit()
	return ""

func can_write(id: String) -> bool:
	if not bundle.people.has(id) or not active_action.is_empty() or flag("ending") != "": return false
	if not person_flag(id, "discovered") or person_flag(id, "status") == "dead": return false
	for entry in pending:
		if entry.person == id: return false
	return true

func write_name(id: String) -> String:
	if not can_write(id): return "当前不能书写这个名字。"
	pending.append({"person": id, "name": person_name(id), "valid": person_flag(id, "identity") == 100, "day": int(flag("day"))})
	_log("你写下了「%s」。墨水慢慢干了。\n窗外的车流声没有变化。" % person_name(id))
	EventBus.custom_event.emit("notebook_written", {"person": id})
	changed.emit()
	return ""

func end_day() -> String:
	if not active_action.is_empty() or flag("ending") != "": return "当前不能结束一天。"
	var candidate := GameState.snapshot()
	var messages: Array = []
	for entry in pending:
		if entry.valid:
			candidate.flags["person." + entry.person + ".status"] = "dead"
			candidate.flags.writes += 1
			candidate.flags.erosion += 1
			_apply(candidate, bundle.people[entry.person].death_effects)
			messages.append(bundle.people[entry.person].death_text)
		else:
			candidate.flags.wrong_writes += 1
			messages.append("黑页上的「%s」被一道细痕划掉。\n没有相关死亡消息。那道痕迹却留在纸上。" % entry.name)
	candidate.flags.day += 1
	candidate.flags.actions_left = 3
	for id in bundle.events:
		var event: Dictionary = bundle.events[id]
		if not candidate.flags["event." + id + ".done"] and Rules.matches(event.get("requires", []), candidate.flags, candidate.inventory):
			_apply(candidate, event.get("effects", {}))
			candidate.flags["event." + id + ".done"] = true
			messages.append(event.text)
	var error: String = GameState.validate_snapshot(candidate)
	if not error.is_empty(): return "结算失败，状态未改变：" + error
	GameState.restore(candidate)
	pending.clear()
	_log("第 %d 天\n%s" % [int(flag("day")), "\n\n".join(messages) if not messages.is_empty() else "雨还在下。手机暂时没有新的消息。"])
	EventBus.custom_event.emit("day_settled", {"day": flag("day")})
	changed.emit()
	return ""

func finish_case(choice: String) -> String:
	if choice not in ["seal", "keep"] or not active_action.is_empty() or flag("ending") != "": return "当前不能结束首章。"
	if flag("day") < 2: return "至少完成第一天的调查。"
	# Both writing and abstaining receive next-day feedback before the ending.
	var error := end_day()
	if not error.is_empty(): return error
	error = GameState.apply({"set": {"decision": choice}})
	if not error.is_empty(): return error
	for ending in bundle.endings:
		if matches(ending.get("requires", [])):
			GameState.apply({"set": {"ending": ending.id}})
			_log(ending.name + "\n" + ending.text)
			EventBus.ending_reached.emit(ending.id, "")
			break
	changed.emit()
	return ""

func _apply(candidate: Dictionary, effects: Dictionary) -> void:
	candidate.flags.merge(effects.get("set", {}), true)
	for id in effects.get("add", {}): candidate.flags[id] += effects.add[id]
	for id in effects.get("inventory", {}):
		candidate.inventory[id] = candidate.inventory.get(id, 0) + effects.inventory[id]
		if candidate.inventory[id] == 0: candidate.inventory.erase(id)

func _log(message: String) -> void:
	journal.append(message)
	if journal.size() > 100: journal.pop_front()

func snapshot() -> Dictionary:
	return {"schema": 1, "content": "black_page_mvp", "state": GameState.snapshot(), "pending": pending.duplicate(true), "journal": journal.duplicate()}

func validate_save(data: Dictionary, definitions: Dictionary, catalog: Dictionary, content: Dictionary = {}) -> String:
	if content.is_empty(): content = bundle
	if data.get("schema") != 1 or data.get("content") != "black_page_mvp": return "存档版本或游戏不匹配。"
	if not data.get("state") is Dictionary or not data.get("pending") is Array or not data.get("journal") is Array: return "存档结构损坏。"
	var error: String = GameState.validate_snapshot(data.state, definitions, catalog)
	if not error.is_empty(): return error
	var restored: Dictionary = {}
	for id in definitions: restored[id] = definitions[id].default
	restored.merge(data.state.flags, true)
	if not str(restored.ending).is_empty():
		var found := false
		for ending in content.endings:
			if ending.id == restored.ending: found = true
		if not found: return "结局 ID 已不存在。"
	if data.pending.size() > content.people.size() or data.journal.size() > 100: return "存档记录数量异常。"
	var seen: Array = []
	for entry in data.pending:
		if not entry is Dictionary or not content.people.has(entry.get("person")) or not entry.get("valid") is bool or not entry.get("name") is String or not Rules.integer(entry.get("day")): return "落笔记录损坏。"
		if entry.person in seen or entry.day != restored.day or restored["person." + entry.person + ".status"] == "dead" or restored.ending != "": return "落笔记录与世界状态冲突。"
		seen.append(entry.person)
	for message in data.journal:
		if not message is String: return "日志格式错误。"
	return ""

func restore(data: Dictionary) -> String:
	var error := validate_save(data, bundle.flags, bundle.catalog)
	if not error.is_empty(): return error
	cancel_action()
	GameState.restore(data.state)
	pending = data.pending.duplicate(true)
	journal = data.journal.duplicate()
	changed.emit()
	return ""

func save_game() -> String:
	if not active_action.is_empty(): return "调查结束后才能存档。"
	return Store.new().write("black_page_slot_1", snapshot())

func load_game() -> String:
	var loaded: Dictionary = Store.new().read("black_page_slot_1")
	return str(loaded.error) if loaded.has("error") else restore(loaded.data)

func reload_data() -> String:
	if not active_action.is_empty(): return "请先结束当前调查再重载。"
	var loader = Loader.new()
	var candidate: Dictionary = loader.compile(directory)
	if not loader.error.is_empty(): return loader.error
	var error := validate_save(snapshot(), candidate.flags, candidate.catalog, candidate)
	if not error.is_empty(): return "热重载被拒绝：" + error
	var state := GameState.snapshot()
	bundle = candidate
	GameState.configure(bundle)
	GameState.restore(state)
	EventBus.story_reloaded.emit()
	changed.emit()
	return ""
