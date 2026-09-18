extends Node
## 调查编排。GameState 仍是强类型状态的唯一持有者——本模块是唯一允许写它的地方。
signal changed
const Loader = preload("res://scripts/black_page/data_loader.gd")
const Rules = preload("res://scripts/core/rules.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
## 存档槽名只在这里出现一次：写、读、「有没有存档」都走它。
const SLOT := "black_page_slot_1"
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
	# 日志留空：开场正文**是剧情数据**（stories.json 的 chapter1_open），
	# 由叙事执行器播出来、顺手记进日志。这里不再硬编码文字——
	# 改台词只改数据文件，代码不掺内容。
	journal = []
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

## 剧情 / 数据用的完整 effects 口子（set / add / inventory 三件套）。
## apply_state 只收「纯 set」——那是最常用的一种；这里是全形态，给执行器用。
func apply_effects(effects: Dictionary) -> String:
	if effects.is_empty(): return ""
	var error: String = GameState.apply(effects)
	if not error.is_empty(): return error
	changed.emit()
	return ""

## 剧情正文进日志。**只记不广播**：台词马上要演，广播会让界面先刷一次
## 「最新一条」，和正在打的字打架；演完或状态变化时自然会刷新。
func log_narrative(text: String) -> void:
	_log(text)

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

## 一条线索现在该显示的正文：取第一个条件满足的变体，否则用基础描述。
##
## 为什么需要它：同一条线索在不同来路下正文不一样——「许妍留下的证词」是赴约
## 听来的完整版，还是从旧手机打捞的半条语音，读起来完全不同。以前这个判断硬编码
## 在界面里（对 testimony 的特判），换一条线索就要再改一次界面；现在由线索自己在
## 数据里声明变体，界面只问「这条线索现在该显示什么」。
func clue_description(id: String) -> String:
	var clue: Dictionary = bundle.clues[id]
	for variant in clue.get("variants", []):
		if matches(variant.get("requires", [])): return variant.description
	return clue.description

## 给一条线索（剧情模块用）。已有这条线索时静默跳过——
## 剧情可能因为读档重播后半段，跳过让重复执行变成无害。
func add_clue(id: String) -> String:
	if not bundle.clues.has(id): return "未知线索：" + id
	var candidate := GameState.snapshot()
	if not _grant_clue(candidate, id): return ""
	var error: String = GameState.validate_snapshot(candidate)
	if not error.is_empty(): return error
	GameState.restore(candidate)
	_log("获得线索：" + str(bundle.clues[id].name))
	changed.emit()
	return ""

## 把一条线索写进候选状态（含线索自带的 effects）。已有则不动，返回 false。
## complete_action 和 add_clue 共用它：两处的语义必须一模一样，
## 不许一边「已有就跳过」、另一边「已有也重写」。
func _grant_clue(candidate: Dictionary, id: String) -> bool:
	if candidate.inventory.has(id): return false
	candidate.inventory[id] = 1
	_apply(candidate, bundle.clues[id].get("effects", {}))
	return true

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

## 提交一次调查。**除了「可以重试」的中断，任何失败路径都不许把行动锁留在身上**——
## 锁不释放，玩家就卡在「不能开始新调查、不能存档、不能重载数据」的死角里，
## 只有重新开始能出去。所以每个 return 之前都问一句：锁放了吗？
func complete_action(token: int, result: Dictionary = {}) -> String:
	if token != ticket or active_action.is_empty(): return "调查回调已过期。"
	var id := active_action
	var action: Dictionary = bundle.actions[id]
	# 小游戏没做完可以重试：弹层还开着，锁留着不碍事。
	if action.kind == "minigame" and result.get("success") != true: return "尚未完成还原；可以重试或返回。"
	if not available(id):
		# 状态零变化，只是这条方向不能走了——锁放掉，让玩家能继续。
		cancel_action()
		return "调查方向发生变化，请返回。"
	var candidate := GameState.snapshot()
	var gained: Array = []
	for clue in action.clues:
		if _grant_clue(candidate, clue):
			gained.append(bundle.clues[clue].name)
	_apply(candidate, action.get("effects", {}))
	candidate.flags["action." + id + ".done"] = true
	candidate.flags.actions_left -= 1
	var error: String = GameState.validate_snapshot(candidate)
	if not error.is_empty():
		# 事务回滚（什么都没写），但锁要放——不然一条坏数据能把整局锁死。
		cancel_action()
		return error
	GameState.restore(candidate)
	cancel_action()
	_log(action.text + ("\n获得线索：" + "、".join(gained) if not gained.is_empty() else ""))
	var day_error := ""
	if flag("actions_left") == 0:
		# 行动点用尽自动进次日。次日结算失败必须往上报：
		# 只写日志的话，玩家会停在「0 次行动、日子也不前进」的死角里，
		# 而且看不出发生了什么。
		day_error = end_day()
		if not day_error.is_empty(): _log(day_error)
	changed.emit()
	return day_error

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
	candidate.flags.actions_left = int(bundle.flags.actions_left.max)
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
	if journal.size() > SaveManager.JOURNAL_CAP: journal.pop_front()

func snapshot() -> Dictionary:
	return SaveManager.payload(GameState.snapshot(), pending, journal)

## 存档格式的校验在 save_manager 里；这里只负责把「当前 bundle」补上——
## 它不持有游戏数据，问不了 bundle。
func validate_save(data: Dictionary, definitions: Dictionary, catalog: Dictionary, content: Dictionary = {}) -> String:
	if content.is_empty(): content = bundle
	return SaveManager.validate(data, definitions, catalog, content)

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
	return SaveManager.write(SLOT, snapshot())

func load_game() -> String:
	var loaded: Dictionary = SaveManager.read(SLOT)
	return str(loaded.error) if loaded.has("error") else restore(loaded.data)

## 有没有**真的能续**的存档。开始页据此决定要不要显示「继续游戏」——
## 只查文件读不读得出来是不够的：内容过不了校验（版本不符 / 结构损坏 /
## 引用了已经不存在的结局）时，「继续游戏」点下去只会把错误打在
## 开始页看不见的字幕带上，玩家会以为游戏坏了。
## slot 参数只为测试留口子，游戏里一律走默认槽位。
func has_save(slot: String = SLOT) -> bool:
	var loaded: Dictionary = SaveManager.read(slot)
	if loaded.has("error"): return false
	return validate_save(loaded.data, bundle.flags, bundle.catalog).is_empty()

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
	changed.emit()
	return ""
