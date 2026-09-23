extends Node
## 调查编排。GameState 仍是强类型状态的唯一持有者——本模块是唯一允许写它的地方。
signal changed
const Loader = preload("res://scripts/black_page/data_loader.gd")
const Rules = preload("res://scripts/core/rules.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
## 小游戏结果的词表和形状（normalize / passed）在这里只有这一份。
const MiniGameResult = preload("res://scripts/core/minigame_result.gd")
## 图鉴的读模型与解锁校验（设计文档 §12-14）。
const CodexManager = preload("res://scripts/core/codex_manager.gd")
## 案件状态机与单活动不变量（设计文档 §15-17）。
const CaseManager = preload("res://scripts/core/case_manager.gd")
## 死亡笔记的世界规则：能不能写、写下去兑现成什么。**只有一份**——
## 这里的 write_name / end_day 和界面上的提示读的都是它。
const DeathNoteSystem = preload("res://scripts/core/death_note_system.gd")
## 正式存档的槽名（写、读、「有没有存档」都走它）。
const SLOT := "black_page_slot_1"
var save_slot := SLOT
## 落笔前的自动检查点（「回溯至使用死亡笔记之前」读的就是这个槽）。
## **和正式存档分开两个槽**：笔记的动作不该挤掉玩家自己的存档，
## 而它必须在落笔之后仍然活着——回溯正是回来读它。
var checkpoint_slot := "black_page_slot_checkpoint"
var bundle: Dictionary = {}
var journal: Array = []
var pending: Array = []
var active_action := ""
var ticket := 0
var directory := "res://data/black_page"
var last_save_recovered := false

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
	last_save_recovered = false
	pending.clear()
	# 检查点属于上一局的世界：留着它，新世界的「回溯」就可能退到别人的剧情里。
	SaveManager.erase(checkpoint_slot)
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

## 记录一局小游戏的结果（打完 / 中途退出都算，退出记 cancelled）。
##
## **小游戏不决定剧情**（设计文档 §9.3）：这里只把「打成什么样」落进
## `minigame.<id>.type` / `.score`，给什么由剧情用 if 查、由结算用 passed() 判。
## 每次打完都覆盖——记的是「最近一局」；重试就是把上次的记录改掉。
func note_minigame(id: String, raw: Variant) -> String:
	if not bundle.minigames.has(id): return "未知小游戏：" + id
	var result: Dictionary = MiniGameResult.normalize(raw)
	var candidate := GameState.snapshot()
	candidate.flags["minigame." + id + ".type"] = result.type
	candidate.flags["minigame." + id + ".score"] = result.score
	var error: String = GameState.validate_snapshot(candidate)
	if not error.is_empty(): return error
	GameState.restore(candidate)
	changed.emit()
	return ""

## 认识一个人（设计文档 §12：图鉴解锁由剧情驱动——`unlock` 指令走这里）。
## 已经认识过就无事发生——剧情可能因为读档重播后半段，重复执行必须无害。
func unlock_person(id: String) -> String:
	if not bundle.people.has(id): return "未知人物：" + id
	if person_flag(id, "discovered") == true: return ""
	return _unlock({"person." + id + ".discovered": true})

## 读到一条档案条目（`unlockinfo` 指令走这里，设计文档 §13 的分阶段解锁）。
## 前置是「已经认识这个人」：不认识就想读他的档案，一定是数据写错了，
## 拦下来——不然图鉴里会冒出无主条目，玩家看到名字却不知道该点谁。
func unlock_person_info(id: String, field: String) -> String:
	var error := CodexManager.unlock_error(bundle, id, field)
	if not error.is_empty(): return error
	if person_flag(id, "discovered") != true: return "还没有认识这个人：" + id
	if person_flag(id, "info." + field) == true: return ""
	return _unlock({"person." + id + ".info." + field: true})

## 打开过这个人的图鉴页 = 看过了（清掉「有新东西」的小红点）。
## **只清痕迹、不动内容**：浏览不是获取，解锁永远由剧情/线索驱动（§12.1）。
func mark_codex_read(id: String) -> String:
	if person_flag(id, "codex_new") != true: return ""
	return apply_state({"person." + id + ".codex_new": false})

## 解锁写入的公共事务（认识一个人、读到一条档案都走它）。
## 和普通 set 的区别：解锁是「玩家知道的东西变多了」——图鉴要亮小红点，
## 所以统一过 _apply（那里会顺手点 codex_new），再照常校验、提交、广播。
func _unlock(changes: Dictionary) -> String:
	var candidate := GameState.snapshot()
	_apply(candidate, {"set": changes})
	var error: String = GameState.validate_snapshot(candidate)
	if not error.is_empty(): return error
	GameState.restore(candidate)
	changed.emit()
	return ""

## 结案（设计文档 §15-16）：把进行中的案件推到 completed，落定结果。
## 结果不是调用方给的字符串，而是案件数据里的 outcomes 裁定出来的——
## 调用方只说「结案了」，代码不问结果叫什么。
func complete_case() -> String:
	var id := CaseManager.active_case(bundle, GameState.flags)
	if id.is_empty(): return "没有进行中的案件。"
	var result := _case_outcome(id)
	if result.is_empty(): return "案件「%s」没有一个结果的条件成立。" % id
	var candidate := GameState.snapshot()
	candidate.flags["case." + id + ".state"] = "completed"
	candidate.flags["case." + id + ".result"] = result
	var error: String = GameState.validate_snapshot(candidate)
	if not error.is_empty(): return error
	GameState.restore(candidate)
	changed.emit()
	return ""

## 这个案子该记什么结果：取案件数据里第一条条件成立的（cases.json 的 outcomes）。
## 「查得多清楚算哪个结果」是**这一个案子**的叙事裁定，不是引擎知识——
## 换案子、换判定，改数据就行。
func _case_outcome(id: String) -> String:
	for outcome in bundle.cases[id].get("outcomes", []):
		if matches(outcome.get("requires", [])): return str(outcome.result)
	return ""

## 案件现在**够格**记什么结果（读模型，给界面显示进展用）。
## 空串 = 没有进行中的案件、或现在结案只能走无条件兜底（也就是「还没查明白」）。
## 判定规则仍只有 _case_outcome 一份——这里只回答「是不是兜底」。
func case_outlook(id: String) -> String:
	if not bundle.cases.has(id) or str(flag("case." + id + ".state")) != "active": return ""
	var outcomes: Array = bundle.cases[id].get("outcomes", [])
	if outcomes.is_empty(): return ""
	var outcome := _case_outcome(id)
	if outcome == str((outcomes.back() as Dictionary).get("result", "")): return ""
	return outcome

func available(id: String) -> bool:
	if not bundle.actions.has(id) or flag("ending") != "": return false
	return not flag("action." + id + ".done") and matches(bundle.actions[id].get("requires", []))

func begin_action(id: String) -> String:
	if not active_action.is_empty(): return "请先结束当前调查。"
	if not available(id): return "这条调查方向已经不可用。"
	active_action = id
	ticket += 1
	return ""

func cancel_action() -> void:
	active_action = ""
	ticket += 1

## 提交一次调查。**除了「可以重试」的中断，任何失败路径都不许把行动锁留在身上**——
## 锁不释放，玩家就卡在「不能开始新调查、不能存档、不能重载数据」的死角里，
## 只有重新开始能出去。所以每个 return 之前都问一句：锁放了吗？
##
## 小游戏的结果不从参数进来：打完时它已经落进状态（note_minigame），
## 这里读 `minigame.<id>.type` 判断——状态是唯一真相源，谁调都一样。
func complete_action(token: int) -> String:
	if token != ticket or active_action.is_empty(): return "调查回调已过期。"
	var id := active_action
	var action: Dictionary = bundle.actions[id]
	# 小游戏没通过可以重试：弹层还开着，锁留着不碍事。
	if action.kind == "minigame" and not MiniGameResult.passed(str(flag("minigame." + str(action.minigame) + ".type"))):
		return "小游戏还没通过；可以重试或返回。"
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
	var error: String = GameState.validate_snapshot(candidate)
	if not error.is_empty():
		# 事务回滚（什么都没写），但锁要放——不然一条坏数据能把整局锁死。
		cancel_action()
		return error
	GameState.restore(candidate)
	cancel_action()
	_log(action.text + ("\n获得线索：" + "、".join(gained) if not gained.is_empty() else ""))
	# 调查不推进时间：日子由玩家在顶栏自己翻（舍弃行动点，重构文档 §18）。
	changed.emit()
	return ""

## 现在为什么不能写这个名字；能写就返回空串。
##
## 界面上的提示（黑页面板）和 write_name 的守卫读的是**同一份判断**——
## 各判一份就会漂，漂了就出现「点亮了却写不进去」这种自相矛盾。
## 前三问是全局闸门（本模块的守卫），名字本身的规矩在 DeathNoteSystem。
func write_error(id: String) -> String:
	if not active_action.is_empty(): return "先结束当前调查。"
	if flag("ending") != "": return "首章已经落幕。"
	return DeathNoteSystem.write_error(bundle, GameState.flags, pending, id)

## 落笔。**先存检查点，再上纸**——这一步写下去可能把世界写断，
## 断了要能退回到「那一笔还没有写下」的时候（设计文档 §28：写错也不会毁档）。
## 检查点失败就不落笔：没有安全网的落笔违背了这条承诺，宁可让玩家重试。
func write_name(id: String) -> String:
	var blocked := write_error(id)
	if not blocked.is_empty(): return blocked
	var check_error := SaveManager.write(checkpoint_slot, snapshot(), false)
	if not check_error.is_empty(): return "无法写下这一笔（检查点未存下）：" + check_error
	pending.append({"person": id, "name": person_name(id), "valid": DeathNoteSystem.knows_true_name(GameState.flags, id), "day": int(flag("day"))})
	_log("你写下了「%s」。墨水慢慢干了。\n窗外的车流声没有变化。" % person_name(id))
	changed.emit()
	return ""

## 回溯：把世界拨回**使用死亡笔记之前**（落笔时自动存下的检查点）。
##
## 断链面板上那条退路走这里。**检查点不被消费**——退回去之后玩家可能又写、
## 又断，那一次回溯读的还是它，重复回溯是幂等的。
## 拒绝条件只有一个：调查进行中（半空中的调查带不过去，行动锁也对不上）。
func roll_back() -> String:
	if not active_action.is_empty(): return "请先结束当前调查。"
	var loaded: Dictionary = SaveManager.read(checkpoint_slot)
	return str(loaded.error) if loaded.has("error") else restore(loaded.data)

## 有没有**可以真的回溯**的检查点。断链面板据此决定给不给那条退路——
## 读得出来还不够，内容要过得了校验（和「继续游戏」同一把尺子：
## 过不了的存档点下去只会把错误打在看不见的字幕带上）。
func checkpoint_ready() -> bool:
	return has_save(checkpoint_slot)

## 结束今天：兑现落笔（死亡 / 划痕）、天数 +1、跑定时事件。
## **日子由玩家自己推**（顶栏的「进入次日」）——没有行动预算、也没有自动跳日，
## 所以这里是唯一的推进入口，守卫（调查进行中 / 已落幕）都留在这里。
func end_day() -> String:
	if not active_action.is_empty() or flag("ending") != "": return "当前不能结束一天。"
	var candidate := GameState.snapshot()
	var messages: Array = []
	# 落笔怎么兑现（写对 / 划痕、代价怎么记、连锁写在哪）是死亡笔记的规则，
	# 在 DeathNoteSystem 里只有一份；这里只管事务：在副本上兑现，过不了校验就整体作废。
	for entry in pending:
		messages.append(DeathNoteSystem.realize(candidate, bundle, entry, _apply))
	candidate.flags.day += 1
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
	# 首章落幕 = 案件结案（设计文档 §16）。失败**不拦结局**：结局已经落了，
	# 这里报错没有可恢复的路径，只会把玩家卡在一个没有出路的房间里。
	var close_error := complete_case()
	if not close_error.is_empty(): push_warning("结案未完成：" + close_error)
	changed.emit()
	return ""

func _apply(candidate: Dictionary, effects: Dictionary) -> void:
	var before: Dictionary = candidate.flags.duplicate()
	candidate.flags.merge(effects.get("set", {}), true)
	for id in effects.get("add", {}): candidate.flags[id] += effects.add[id]
	for id in effects.get("inventory", {}):
		candidate.inventory[id] = candidate.inventory.get(id, 0) + effects.inventory[id]
		if candidate.inventory[id] == 0: candidate.inventory.erase(id)
	# 「图鉴里有新东西」由**写入本身**推出来，不靠数据作者记得补一笔：
	# 数据里写的是解锁（discovered / info.<条目>），小红点是它的痕迹。
	# 挂在这里 = 所有解锁路径一视同仁（线索 / 行动 / 死亡波及 / 剧情 / 以后新加的）。
	for person in CodexManager.touched(before, candidate.flags):
		candidate.flags["person." + person + ".codex_new"] = true

func _log(message: String) -> void:
	journal.append(message)
	if journal.size() > SaveManager.JOURNAL_CAP: journal.pop_front()

func snapshot() -> Dictionary:
	return SaveManager.payload(GameState.snapshot(), pending, journal)

## 存档格式的校验在 save_manager 里；这里只负责把「当前 bundle」补上——
## 它不持有游戏数据，问不了 bundle。
func validate_save(data: Dictionary, definitions: Dictionary, catalog: Dictionary, content: Dictionary = {}) -> String:
	if content.is_empty(): content = bundle
	var prepared: Dictionary = SaveManager.prepare(data, definitions, catalog, content)
	return str(prepared.error) if prepared.has("error") else ""

func restore(data: Dictionary) -> String:
	var prepared: Dictionary = SaveManager.prepare(data, bundle.flags, bundle.catalog, bundle)
	if prepared.has("error"): return str(prepared.error)
	_restore_validated(prepared.data)
	return ""

func _restore_validated(data: Dictionary) -> void:
	cancel_action()
	GameState.restore(data.state)
	pending = data.pending.duplicate(true)
	journal = data.journal.duplicate()
	last_save_recovered = false
	changed.emit()

func save_game() -> String:
	if not active_action.is_empty(): return "调查结束后才能存档。"
	# 这局若刚从备份读回，主文件可能虽能解析却过不了世界状态校验；
	# 第一次重新保存时保留那份有效备份，避免把坏主档复制到备份上。
	var error := SaveManager.write(save_slot, snapshot(), not last_save_recovered)
	if error.is_empty(): last_save_recovered = false
	return error

func load_game() -> String:
	var loaded: Dictionary = SaveManager.load_validated(save_slot, bundle.flags, bundle.catalog, bundle, true)
	if loaded.has("error"): return str(loaded.error)
	_restore_validated(loaded.data)
	last_save_recovered = bool(loaded.get("recovered", false))
	return ""

## 有没有**真的能续**的存档。开始页据此决定要不要显示「继续游戏」——
## 只查文件读不读得出来是不够的：内容过不了校验（版本不符 / 结构损坏 /
## 引用了已经不存在的结局）时，「继续游戏」点下去只会把错误打在
## 开始页看不见的字幕带上，玩家会以为游戏坏了。
## slot 参数：检查点回溯（checkpoint_ready）也走它；游戏里一律走默认槽位。
func has_save(slot: String = "") -> bool:
	var target := save_slot if slot.is_empty() else slot
	return not SaveManager.load_validated(target, bundle.flags, bundle.catalog, bundle, target == save_slot).has("error")

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
