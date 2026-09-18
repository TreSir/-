extends RefCounted
## 把 data/black_page/*.json 编译成 bundle：字段校验 + 跨文件引用检查 + 规范化。
const Source = preload("res://scripts/core/json_source.gd")
const Rules = preload("res://scripts/core/rules.gd")
## 指令流剧情的校验要照着**执行器认识的指令表**来：加指令只改执行器一处，这里自动跟上。
const Runner = preload("res://scripts/core/narrative_runner.gd")
## 演出数据的校验同理，照着**导演认识的动作表**来（performance_director.gd）。
const Director = preload("res://scripts/black_page/performance_director.gd")
## 小游戏结果的类型词表也读代码里那一张（core/minigame_result.gd）。
const MiniGameResult = preload("res://scripts/core/minigame_result.gd")
## 案件状态的词表（locked / active / completed）读代码里那一张（core/case_manager.gd）。
const CaseManager = preload("res://scripts/core/case_manager.gd")
## 图鉴条目的校验走图鉴管理器的读模型（core/codex_manager.gd）——
## 「什么算一条合法档案」只有它说了算。
const CodexManager = preload("res://scripts/core/codex_manager.gd")
var sources: Dictionary = {}
var error := ""

func compile(directory: String = "res://data/black_page") -> Dictionary:
	sources.clear()
	error = ""
	var result: Dictionary = {"id": "black_page", "catalog": {"items": {}}}
	for name in ["flags", "people", "clues", "actions", "cases", "events", "endings", "codex", "transitions", "prologue", "sequences", "stories", "minigames"]:
		var source = Source.new()
		source.read_file(directory.path_join(name + ".json"))
		sources[name] = source
		if not source.error.is_empty():
			error = source.error
			return {}
		if (name == "endings" and not source.data is Array) or (name != "endings" and not source.data is Dictionary):
			_fail(name, "", "文件根类型错误")
			return {}
		result[name] = source.data
	# 序章也走这条管线：规范成统一的页数组，字段写错在这里就报出来，
	# 而不是等到运行时「这一页什么都不显示」。
	result.prologue = _compile_prologue(result.prologue)
	if not error.is_empty():
		return {}
	for id in result.flags:
		var definition: Variant = result.flags[id]
		if not definition is Dictionary or not definition.has("default"):
			_fail("flags", "/" + id, "缺少类型或默认值")
			return {}
		var message: String = Rules.value_error(definition.default, definition)
		if not message.is_empty():
			_fail("flags", "/" + id, message)
			return {}
	for id in {"day": "int", "writes": "int", "wrong_writes": "int", "erosion": "int", "decision": "string", "ending": "string"}:
		var expected: String = "string" if id in ["decision", "ending"] else "int"
		if not result.flags.has(id) or result.flags[id].get("type") != expected:
			_fail("flags", "/" + id, "缺少或修改了结算核心 Flag 类型：" + id)
			return {}
	# 日子由玩家自己推（舍弃行动点，重构文档 §18），没有每日预算要跟数据对账；
	# 只剩一个默认值要守：第一天是「第 1 天」。
	if result.flags.day.default != 1:
		_fail("flags", "", "day 必须从 1 开始")
		return {}
	for id in result.clues:
		result.catalog.items[id] = {"name": str(id), "max_stack": 1}
	for group in ["people", "clues", "actions", "cases", "events"]:
		for id in result[group]:
			var row: Variant = result[group][id]
			if not row is Dictionary:
				_fail(group, "/" + id, "条目必须为对象")
				return {}
			if not _validate_row(group, id, row, result): return {}
	var ids: Array = []
	var priorities: Array = []
	var fallback := 0
	for i in result.endings.size():
		var row: Variant = result.endings[i]
		if not row is Dictionary or not row.get("id") is String or not row.get("text") is String or not row.get("name") is String or not Rules.integer(row.get("priority")):
			_fail("endings", "/" + str(i), "结局字段不完整")
			return {}
		if row.id in ids or row.priority in priorities:
			_fail("endings", "/" + str(i), "结局 ID / 优先级重复")
			return {}
		ids.append(row.id)
		priorities.append(row.priority)
		if row.get("requires", []).is_empty(): fallback += 1
		if not _rules("endings", "/" + str(i), row, result): return {}
	if fallback != 1:
		_fail("endings", "", "必须有且仅有一个无条件兜底结局")
		return {}
	result.endings.sort_custom(func(a: Dictionary, b: Dictionary): return a.priority > b.priority)
	if not result.endings.back().get("requires", []).is_empty():
		_fail("endings", "", "兜底结局必须具有最低优先级")
		return {}
	if not _compile_sequences(result): return {}
	if not _compile_minigames(result): return {}
	if not _compile_codex(result): return {}
	if not _compile_stories(result): return {}
	return result

func _validate_row(group: String, id: String, row: Dictionary, bundle: Dictionary) -> bool:
	var pointer := "/" + id
	if group != "events" and not row.get("name") is String:
		return _fail(group, pointer, "缺少 name")
	if group in ["people", "clues", "actions"] and not bundle.cases.has(row.get("case")):
		return _fail(group, pointer + "/case", "未知案件引用")
	if not _rules(group, pointer, row, bundle): return false
	match group:
		"people":
			for field in ["real_name", "role", "description", "death_text"]:
				if not row.get(field) is String: return _fail(group, pointer, "缺少 " + field)
			var message: String = Rules.effects_error(row.get("death_effects", {}), bundle.flags, bundle.catalog)
			if not message.is_empty(): return _fail(group, pointer + "/death_effects", message)
			for field in ["identity", "truth", "status", "discovered", "codex_new"]:
				if not bundle.flags.has("person." + id + "." + field): return _fail(group, pointer, "缺少人物状态声明 " + field)
		"clues":
			if not row.get("description") is String or not row.get("type") is String or not row.get("people") is Array:
				return _fail(group, pointer, "缺少线索描述、类型或人物列表")
			for person in row.people:
				if not bundle.people.has(person): return _fail(group, pointer + "/people", "未知人物")
			if not bundle.flags.has("clue." + id + ".reliability"): return _fail(group, pointer, "缺少可信度声明")
			# 线索变体：换一条来路的正文。requires 走和别处同一套条件校验，
			# 写错的旗标名在这里就报出来。
			var variants: Variant = row.get("variants", [])
			if not variants is Array: return _fail(group, pointer + "/variants", "variants 必须为数组")
			for index in variants.size():
				var variant: Variant = variants[index]
				if not variant is Dictionary or not variant.get("description") is String:
					return _fail(group, pointer + "/variants/" + str(index), "变体缺少 description")
				var variant_error: String = Rules.conditions_error(variant.get("requires", []), bundle.flags, bundle.catalog)
				if not variant_error.is_empty():
					return _fail(group, pointer + "/variants/" + str(index) + "/requires", variant_error)
		"actions":
			if row.get("kind") not in ["dialogue", "document", "minigame"] or not row.get("text") is String or not row.get("clues") is Array:
				return _fail(group, pointer, "调查类型、正文或奖励格式错误")
			if not bundle.flags.has("action." + id + ".done"): return _fail(group, pointer, "缺少完成状态声明")
			for clue in row.clues:
				if not bundle.clues.has(clue): return _fail(group, pointer + "/clues", "未知线索 " + str(clue))
			if row.kind == "minigame":
				# 小游戏本体（场景 / 参数）在 minigames.json 里定义，动作只引用 id——
				# 同一局游戏因此能被别的动作和剧情复用。
				if not row.get("minigame") is String or not bundle.minigames.has(row.minigame):
					return _fail(group, pointer + "/minigame", "未知小游戏：" + str(row.get("minigame")))
		"events":
			if not row.get("text") is String or not bundle.flags.has("event." + id + ".done"): return _fail(group, pointer, "事件缺少文本或完成声明")
		"cases":
			if not row.get("intro") is String or not row.get("questions") is Array: return _fail(group, pointer, "案件缺少介绍或疑点")
			# 案件状态机：三档词表读 CaseManager.STATES——数据少写一档就报错，
			# 不让运行时出现「切不进去 / 切不出去」的状态。
			var state_key := "case." + id + ".state"
			if not bundle.flags.has(state_key) or not bundle.flags.has("case." + id + ".result"):
				return _fail(group, pointer, "缺少案件状态声明：" + state_key + " 与 case." + id + ".result")
			var states: Variant = bundle.flags[state_key].get("values")
			if not states is Array:
				return _fail(group, pointer, state_key + " 必须声明 values（状态词表）")
			for state in CaseManager.STATES:
				if not state in states: return _fail(group, pointer, state_key + " 少了状态：" + state)
			# 结案结果：results 是词表，outcomes 是裁定规则（条件 → 结果）。
			# 最后一条必须无条件兜底——不然「查了半天、结案时落个空结果」会静默发生。
			var results: Variant = row.get("results")
			if not results is Array or (results as Array).is_empty():
				return _fail(group, pointer, "缺少 results（结案结果词表）")
			var result_values: Variant = bundle.flags["case." + id + ".result"].get("values")
			if not result_values is Array:
				return _fail(group, pointer, "case." + id + ".result 必须声明 values（结果词表）")
			for result in results:
				if not result in result_values: return _fail(group, pointer + "/results", "结果旗标里没有这个词：" + str(result))
			var outcomes: Variant = row.get("outcomes")
			if not outcomes is Array or (outcomes as Array).is_empty():
				return _fail(group, pointer, "缺少 outcomes（结果裁定）")
			for i in (outcomes as Array).size():
				var outcome: Variant = outcomes[i]
				var outcome_pointer := pointer + "/outcomes/" + str(i)
				if not outcome is Dictionary or not outcome.get("result") is String:
					return _fail(group, outcome_pointer, "裁定缺少 result")
				if not outcome.result in results:
					return _fail(group, outcome_pointer + "/result", "结果不在 results 里：" + str(outcome.result))
				var outcome_error: String = Rules.conditions_error(outcome.get("requires", []), bundle.flags, bundle.catalog)
				if not outcome_error.is_empty(): return _fail(group, outcome_pointer + "/requires", outcome_error)
			if not (outcomes as Array).back().get("requires", []).is_empty():
				return _fail(group, pointer + "/outcomes", "最后一条裁定必须无条件兜底")
			for i in row.questions.size():
				var question: Variant = row.questions[i]
				if not question is Dictionary or not question.get("text") is String: return _fail(group, pointer, "疑点格式错误")
				if not _rules(group, pointer + "/questions/" + str(i), question, bundle): return false
	return true

func _rules(group: String, pointer: String, row: Dictionary, bundle: Dictionary) -> bool:
	var message: String = Rules.conditions_error(row.get("requires", []), bundle.flags, bundle.catalog)
	if not message.is_empty(): return _fail(group, pointer + "/requires", message)
	message = Rules.effects_error(row.get("effects", {}), bundle.flags, bundle.catalog)
	if not message.is_empty(): return _fail(group, pointer + "/effects", message)
	return true

## 序章页的字段表：**一行一个字段，值就是这个字段的默认值**。
##
## 校验（认不认识这个名字）和拷贝（取出来、给默认值、做转换）**都从这一张表读**。
##
## 为什么要这样：以前这两件事写在**两个地方**（白名单 + out.append），
## 加字段时必须同时改两处——**只改一处就会静默丢数据**：
## `music` / `sfx` 就这么丢过一次（校验过了、数据没了、音效一个都不响，而测试全绿）。
##
## ★ 以后加字段：**只在这里加一行**，校验和拷贝自动跟上。
const PROLOGUE_FIELDS := {
	"id": "",
	"title": "",
	"body": "",
	"action": "",
	# 新写法是 background；bg 是旧写法（door / note），留着只为不告警。
	"background": "door",
	"bg": "",
	"visual": {},
	"choices": [],
	"hotspots": [],
	"set": {},
	"music": {},
	"sfx": "",
	"speed": 0.0,
}
const PROLOGUE_VISUALS := ["notebook", "profile", "article", "title"]

## 背景别名 → 资源路径。只在这一层翻译；引擎永远不认识具体素材。
const BACKDROP_ALIASES := {
	"door": "res://assets/backgrounds/black_page_prologue_door_v1.png",
	"note": "res://assets/backgrounds/black_page_prologue_notebook_v1.png",
}

## 按字段表取一个值。查不到就用表里的默认值，并按默认值的类型做一次转换。
##
## 转换规则只有三条，按默认值的类型分派，够用且不用给每个字段写代码：
##   字典 / 数组 → 深拷贝（页面之间不能共享同一份，改一页会连带改到别人）
##   浮点        → float()
##   其余        → str()
func _field_of(page: Dictionary, key: String) -> Variant:
	var fallback: Variant = PROLOGUE_FIELDS[key]
	var value: Variant = page.get(key, fallback)
	if fallback is Dictionary:
		return (value as Dictionary).duplicate(true) if value is Dictionary else {}
	if fallback is Array:
		return (value as Array).duplicate(true) if value is Array else []
	if fallback is float:
		return float(value)
	return str(value)

## 把 `prologue.json` 规范化成 bundle.prologue（页数组）。
## 序章因此和 actions / cases 一样吃同一套校验与 F6 热重载。
func _compile_prologue(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Dictionary) or not ((raw as Dictionary).get("pages") is Array):
		_fail("prologue", "", "缺少 pages 数组")
		return out
	var pages: Array = (raw as Dictionary).pages
	for index in pages.size():
		var entry: Variant = pages[index]
		if not (entry is Dictionary):
			_fail("prologue", "/pages/" + str(index), "这一页不是对象")
			return []
		var page: Dictionary = entry
		for key in page:
			# `#` 开头的键当注释用（JSON 不支持注释），不算未知字段。
			if str(key).begins_with("#"): continue
			if not PROLOGUE_FIELDS.has(str(key)):
				push_warning("prologue.json /pages/%d 有未知字段「%s」，会被忽略" % [index, key])
		var visual: Variant = page.get("visual", {})
		var kind := str((visual as Dictionary).get("type", "")) if visual is Dictionary else ""
		if not kind.is_empty() and not kind in PROLOGUE_VISUALS:
			push_warning("prologue.json /pages/%d 的 visual.type「%s」不认得，可用：%s"
				% [index, kind, ", ".join(PROLOGUE_VISUALS)])
		# ★ 拷贝也走同一张表：加字段只改上面的表，这里不用动。
		var compiled: Dictionary = {}
		for key in PROLOGUE_FIELDS:
			compiled[key] = _field_of(page, str(key))
		# 旧写法 bg 的兜底：background 没给才用它。
		if str(compiled.background).is_empty():
			compiled.background = str(page.get("bg", "door"))
		# 别名规范化：**数据进引擎前就变成干净数据**——
		# 引擎（core/scripted.gd）只认 res:// 路径和 "black"，不认识 door / note 这种剧本私有别名。
		compiled.background = str(BACKDROP_ALIASES.get(str(compiled.background), str(compiled.background)))
		out.append(compiled)
	if out.is_empty():
		_fail("prologue", "", "没有任何有效页")
	return out

## 演出数据（sequences.json）的校验：时间轴形状 + 动作参数。
##
## 动作名读导演的 ACTIONS（见 performance_director.gd）——和剧情指令读
## Runner.COMMANDS 一个规矩：加动作只改导演一处，校验自动跟上。
func _compile_sequences(bundle: Dictionary) -> bool:
	for id in bundle.sequences:
		var sequence: Variant = bundle.sequences[id]
		var pointer := "/" + str(id)
		if not sequence is Dictionary: return _fail("sequences", pointer, "演出必须为对象")
		if not sequence.get("name") is String: return _fail("sequences", pointer, "缺少 name")
		var steps: Variant = sequence.get("steps")
		if not steps is Array or (steps as Array).is_empty():
			return _fail("sequences", pointer, "缺少 steps 数组")
		for index in steps.size():
			var step: Variant = steps[index]
			var step_pointer := pointer + "/steps/" + str(index)
			# 一步 = 「at + 一个动作」。同一个 at 可以有多步——那就是同时发生的事。
			if not step is Dictionary or (step as Dictionary).size() != 2:
				return _fail("sequences", step_pointer, "一步必须是一个「at + 动作」的对象")
			var at: Variant = (step as Dictionary).get("at")
			if not (at is float or at is int) or float(at) < 0.0:
				return _fail("sequences", step_pointer + "/at", "at 必须是不小于 0 的秒数")
			var action := ""
			var argument: Variant = null
			for key in step:
				if str(key) != "at":
					action = str(key)
					argument = step[key]
			if not action in Director.ACTIONS:
				return _fail("sequences", step_pointer, "未知动作「%s」，可用：%s" % [action, ", ".join(Director.ACTIONS)])
			if not _validate_performance(action, argument, step_pointer): return false
	return true

func _validate_performance(action: String, argument: Variant, pointer: String) -> bool:
	match action:
		"sfx":
			if not argument is String or not ResourceLoader.exists(argument):
				return _fail("sequences", pointer + "/sfx", "音效文件不存在：" + str(argument))
		"bgm":
			if not argument is String:
				return _fail("sequences", pointer + "/bgm", "bgm 必须是路径，空串表示停")
			if not (argument as String).is_empty() and not ResourceLoader.exists(argument):
				return _fail("sequences", pointer + "/bgm", "音乐文件不存在：" + str(argument))
		"fade_in", "fade_out", "shake", "flash", "wait":
			if not (argument is float or argument is int) or float(argument) <= 0.0:
				return _fail("sequences", pointer + "/" + action, "时长必须是正数")
	return true

## 小游戏（minigames.json）的校验：名字 / 场景存在 / 参数形状，
## 以及**结果旗标的声明齐全**——结果要走 if 被剧情查，就得先有地方落。
##
## 类型值表读 MiniGameResult.TYPES：加一种结果类型只改代码一处，
## 这里自动要求数据把新类型的值补上。
func _compile_minigames(bundle: Dictionary) -> bool:
	for id in bundle.minigames:
		var minigame: Variant = bundle.minigames[id]
		var pointer := "/" + str(id)
		if not minigame is Dictionary: return _fail("minigames", pointer, "小游戏必须为对象")
		if not minigame.get("name") is String: return _fail("minigames", pointer, "缺少 name")
		if not minigame.get("scene") is String or not ResourceLoader.exists(minigame.scene):
			return _fail("minigames", pointer + "/scene", "场景不存在：" + str(minigame.get("scene")))
		if not minigame.get("config") is Dictionary: return _fail("minigames", pointer, "缺少参数 config")
		var type_flag := "minigame." + str(id) + ".type"
		var score_flag := "minigame." + str(id) + ".score"
		if not bundle.flags.has(type_flag) or not bundle.flags.has(score_flag):
			return _fail("minigames", pointer, "缺少结果声明：" + type_flag + " 与 " + score_flag)
		var values: Variant = bundle.flags[type_flag].get("values")
		if not values is Array:
			return _fail("minigames", pointer, type_flag + " 必须声明 values（结果类型词表）")
		for type in MiniGameResult.TYPES:
			if not type in values:
				return _fail("minigames", pointer, type_flag + " 少了结果类型：" + type)
	return true

## 角色图鉴（codex.json）的校验：分阶段解锁的档案条目在这里定形状（设计文档 §13-14）。
##
## 两条硬要求，各守一个静默失败：
##   1. 每条档案都要有声明过的解锁旗标（person.<id>.info.<条目>，bool）——
##      漏声明的话，解锁会写到不存在的旗标上，运行期才炸；
##   2. 图鉴与人物**双向对齐**——少一边就是「这个人打不开图鉴」或者
##      「图鉴里有个不存在的人」。
func _compile_codex(bundle: Dictionary) -> bool:
	for id in bundle.codex:
		var entry: Variant = bundle.codex[id]
		var pointer := "/" + str(id)
		if not bundle.people.has(id): return _fail("codex", pointer, "图鉴里的人物不存在：" + str(id))
		if not entry is Dictionary or not entry.get("fields") is Array:
			return _fail("codex", pointer, "缺少 fields 数组")
		var fields: Array = entry.fields
		if fields.is_empty(): return _fail("codex", pointer, "fields 不能为空")
		var seen: Array = []
		for index in fields.size():
			var field: Variant = fields[index]
			var field_pointer := pointer + "/fields/" + str(index)
			if not field is Dictionary or not field.get("id") is String or not field.get("title") is String or not field.get("text") is String:
				return _fail("codex", field_pointer, "条目字段不完整（id / title / text）")
			if field.id in seen: return _fail("codex", field_pointer, "条目 id 重复：" + str(field.id))
			seen.append(field.id)
			var key := "person." + str(id) + ".info." + str(field.id)
			if not bundle.flags.has(key) or bundle.flags[key].get("type") != "bool":
				return _fail("codex", field_pointer, "缺少（bool）解锁声明：" + key)
	for id in bundle.people:
		if not bundle.codex.has(id): return _fail("codex", "/" + str(id), "人物没有图鉴：" + str(id))
	return true

## 指令流剧情（stories.json）的校验：结构 + 引用 + 指令参数。
##
## 这里**只校验，不改写**：剧情数据进来是什么形状，执行器读到的就是什么形状。
## 指令名读执行器的 COMMANDS（见 narrative_runner.gd）——不认识就报错，
## 不让「数据写了、引擎不认」的步骤活到运行时才静默跳过。
func _compile_stories(bundle: Dictionary) -> bool:
	for id in bundle.stories:
		var story: Variant = bundle.stories[id]
		var pointer := "/" + str(id)
		if not story is Dictionary: return _fail("stories", pointer, "剧情必须为对象")
		if not story.get("name") is String: return _fail("stories", pointer, "缺少 name")
		if not story.get("start") is String: return _fail("stories", pointer, "缺少 start")
		var nodes: Variant = story.get("nodes")
		if not nodes is Dictionary or (nodes as Dictionary).is_empty():
			return _fail("stories", pointer, "缺少 nodes")
		if not nodes.has(story.start): return _fail("stories", pointer + "/start", "start 指向不存在的节点：" + str(story.start))
		for node_id in nodes:
			var node: Variant = nodes[node_id]
			var node_pointer := pointer + "/nodes/" + str(node_id)
			if not node is Dictionary or not node.get("steps") is Array:
				return _fail("stories", node_pointer, "节点缺少 steps 数组")
			# 节点字段照执行器的 NODE_FIELDS 校验（和指令表一个规矩）。
			# 未知字段**直接报错**，不静默忽略：把 requires 拼成 require 之类，
			# 静默的后果就是闸门永远不响——「写了、没执行」正是最难查的那种坏。
			for field in node:
				if not (str(field) in Runner.NODE_FIELDS):
					return _fail("stories", node_pointer + "/" + str(field),
							"节点有未知字段，可用：%s" % ", ".join(Runner.NODE_FIELDS))
			# 节点入口的必要条件（设计文档 §26）：条件本身照常校验，
			# 断了要用节点自己的 broken 文案说清为什么——说不出理由的闸门不许上。
			var required: Variant = node.get("requires", [])
			var requirement: String = Rules.conditions_error(required, bundle.flags, bundle.catalog)
			if not requirement.is_empty(): return _fail("stories", node_pointer + "/requires", requirement)
			var broken: Variant = node.get("broken", "")
			if not broken is String: return _fail("stories", node_pointer + "/broken", "broken 必须是字符串")
			if not (required as Array).is_empty() and (broken as String).strip_edges().is_empty():
				return _fail("stories", node_pointer + "/broken", "有 requires 的节点必须写 broken（断链时要说得出为什么）")
			var steps: Array = node.steps
			for index in steps.size():
				var step: Variant = steps[index]
				var step_pointer := node_pointer + "/steps/" + str(index)
				if not step is Dictionary or (step as Dictionary).is_empty():
					return _fail("stories", step_pointer, "步骤必须是一个非空对象")
				if (step as Dictionary).size() != 1:
					return _fail("stories", step_pointer, "一步只能有一条指令")
				var command := str((step as Dictionary).keys()[0])
				if not command in Runner.COMMANDS:
					return _fail("stories", step_pointer, "未知指令「%s」，可用：%s" % [command, ", ".join(Runner.COMMANDS)])
				if not _validate_story_step(command, step[command], step_pointer, nodes, bundle): return false
	return true

func _validate_story_step(command: String, argument: Variant, pointer: String, nodes: Dictionary, bundle: Dictionary) -> bool:
	match command:
		"say":
			if argument is String: return true
			if argument is Array and not (argument as Array).is_empty():
				for line in argument:
					if not line is String: return _fail("stories", pointer + "/say", "台词必须是字符串")
				return true
			return _fail("stories", pointer + "/say", "台词必须是字符串或字符串数组")
		"effect":
			var message: String = Rules.effects_error(argument, bundle.flags, bundle.catalog)
			if not message.is_empty(): return _fail("stories", pointer + "/effect", message)
			return true
		"clue":
			if not argument is String or not bundle.clues.has(argument):
				return _fail("stories", pointer + "/clue", "未知线索：" + str(argument))
			return true
		"unlock":
			if not argument is String or not bundle.people.has(argument):
				return _fail("stories", pointer + "/unlock", "未知人物：" + str(argument))
			return true
		"unlockinfo":
			if not argument is Dictionary: return _fail("stories", pointer + "/unlockinfo", "unlockinfo 必须为对象")
			var info: Dictionary = argument
			for key in info:
				if key not in ["person", "field"]: return _fail("stories", pointer + "/unlockinfo", "未知字段：" + str(key))
			var info_error: String = CodexManager.unlock_error(bundle, str(info.get("person", "")), str(info.get("field", "")))
			if not info_error.is_empty(): return _fail("stories", pointer + "/unlockinfo", info_error)
			return true
		"sequence":
			if not argument is String or not bundle.sequences.has(argument):
				return _fail("stories", pointer + "/sequence", "未知演出：" + str(argument))
			return true
		"minigame":
			if not argument is String or not bundle.minigames.has(argument):
				return _fail("stories", pointer + "/minigame", "未知小游戏：" + str(argument))
			return true
		"goto":
			return _check_story_node(argument, pointer + "/goto", nodes)
		"if":
			if not argument is Dictionary: return _fail("stories", pointer + "/if", "if 必须为对象")
			var condition: Dictionary = argument
			for key in condition:
				if key not in ["requires", "then", "else"]: return _fail("stories", pointer + "/if", "未知字段：" + str(key))
			var message: String = Rules.conditions_error(condition.get("requires", []), bundle.flags, bundle.catalog)
			if not message.is_empty(): return _fail("stories", pointer + "/if/requires", message)
			if not condition.get("then") is String: return _fail("stories", pointer + "/if", "缺少 then")
			if not _check_story_node(condition.then, pointer + "/if/then", nodes): return false
			if condition.has("else"):
				if not condition.else is String: return _fail("stories", pointer + "/if/else", "else 必须是节点名")
				if not _check_story_node(condition.else, pointer + "/if/else", nodes): return false
			return true
	return true

func _check_story_node(target: Variant, pointer: String, nodes: Dictionary) -> bool:
	if not target is String or not nodes.has(target):
		return _fail("stories", pointer, "指向不存在的节点：" + str(target))
	return true

func _fail(group: String, pointer: String, message: String) -> bool:
	error = sources[group].diagnostic(pointer, message)
	return false
