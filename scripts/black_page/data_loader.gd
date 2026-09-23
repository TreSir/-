extends RefCounted
## 把 data/black_page/*.json 编译成 bundle：字段校验 + 跨文件引用检查 + 规范化。
const Source = preload("res://scripts/core/json_source.gd")
const Rules = preload("res://scripts/core/rules.gd")
## 指令流剧情的校验要照着**执行器认识的指令表**来：加指令只改执行器一处，这里自动跟上。
const Runner = preload("res://scripts/core/narrative_runner.gd")
## 演出数据的校验同理，照着**导演认识的动作表**来（performance_director.gd）。
const Director = preload("res://scripts/black_page/performance_director.gd")
## 剧情 scene 指令的合法场景表。数据在加载期就拦住拼错的场景名。
const Scenes = preload("res://scripts/black_page/scenes.gd")
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
	for name in ["flags", "people", "clues", "actions", "cases", "events", "endings", "codex", "transitions", "sequences", "stories", "minigames"]:
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
	if not _compile_transitions(result): return {}
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
		"title_card":
			if not argument is Dictionary:
				return _fail("sequences", pointer + "/title_card", "标题卡必须为对象")
			var card: Dictionary = argument
			for key in card:
				if key not in ["text", "subtitle", "reveal", "hold", "fade"]:
					return _fail("sequences", pointer + "/title_card", "未知字段：" + str(key))
			if not card.get("text") is String or str(card.get("text", "")).strip_edges().is_empty():
				return _fail("sequences", pointer + "/title_card/text", "标题文字不能为空")
			if card.has("subtitle") and not card.subtitle is String:
				return _fail("sequences", pointer + "/title_card/subtitle", "副标题必须是字符串")
			for field in ["reveal", "hold", "fade"]:
				var value: Variant = card.get(field, 1.0)
				if not (value is float or value is int) or float(value) <= 0.0:
					return _fail("sequences", pointer + "/title_card/" + field, "时长必须是正数")
	return true

## 转场配置（transitions.json）的校验。
##
## 这张表以前一个字都不校验：分组拼成 `scene`、场景 id 写错、kind 写成 "fadee"，
## 全都静默退回默认淡入淡出——配置改了却没生效，是最难查的那种坏。
## 三层优先级（行动 > 场景 > 默认）在 main._transition_config 里合并，这里只管形状。
func _compile_transitions(bundle: Dictionary) -> bool:
	var table: Dictionary = bundle.transitions
	for group in table:
		if group not in ["default", "scenes", "actions"]:
			return _fail("transitions", "/" + str(group), "未知分组，可用：default / scenes / actions")
	if table.has("default") and not _validate_transition(table.get("default"), "/default"):
		return false
	for group in ["scenes", "actions"]:
		var rows: Variant = table.get(group, {})
		if not rows is Dictionary:
			return _fail("transitions", "/" + group, group + " 必须为对象")
		for id in rows:
			var pointer := "/" + str(group) + "/" + str(id)
			# 键本身就是一条引用：写错了永远命中不到，等于白配——和别处同一套查法。
			if group == "scenes" and not Scenes.has(str(id)):
				return _fail("transitions", pointer, "未知场景，这条转场永远用不上：" + str(id))
			if group == "actions" and not bundle.actions.has(str(id)):
				return _fail("transitions", pointer, "未知行动，这条转场永远用不上：" + str(id))
			if not _validate_transition(rows[id], pointer): return false
	return true

## 一条转场配置：字段白名单 + 值形。kind 读场景表里那张词表（scenes.gd.KINDS），
## 和 COMMANDS / ACTIONS 同一个规矩：加一种转场只改一处。
func _validate_transition(config: Variant, pointer: String) -> bool:
	if not config is Dictionary:
		return _fail("transitions", pointer, "转场配置必须为对象")
	for key in config:
		if key not in ["kind", "out", "in", "color"]:
			return _fail("transitions", pointer + "/" + str(key), "未知字段，可用：kind / out / in / color")
	if config.has("kind") and not str(config.kind) in Scenes.KINDS:
		return _fail("transitions", pointer + "/kind",
				"未知转场「%s」，可用：%s" % [str(config.kind), ", ".join(Scenes.KINDS)])
	for field in ["out", "in"]:
		if not config.has(field): continue
		var seconds: Variant = config[field]
		if not (seconds is float or seconds is int) or float(seconds) <= 0.0:
			return _fail("transitions", pointer + "/" + field, "时长必须是正数秒")
	if config.has("color"):
		var hex := str(config.color).lstrip("#")
		if not hex.length() in [6, 8]:
			return _fail("transitions", pointer + "/color", "颜色必须是 6 或 8 位十六进制：" + str(config.color))
		for index in hex.length():
			if "0123456789abcdefABCDEF".find(hex[index]) < 0:
				return _fail("transitions", pointer + "/color", "颜色里有非十六进制字符：" + str(config.color))
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
		"choice":
			if not argument is Dictionary:
				return _fail("stories", pointer + "/choice", "choice 必须为对象")
			var choice: Dictionary = argument
			for key in choice:
				if key not in ["prompt", "options"]:
					return _fail("stories", pointer + "/choice", "未知字段：" + str(key))
			if not choice.get("prompt") is String or str(choice.get("prompt", "")).strip_edges().is_empty():
				return _fail("stories", pointer + "/choice/prompt", "缺少选择提示")
			var options: Variant = choice.get("options")
			if not options is Array or (options as Array).size() < 2:
				return _fail("stories", pointer + "/choice/options", "对话选择至少需要两个选项")
			var labels: Array = []
			var fallback := 0
			for index in (options as Array).size():
				var option: Variant = options[index]
				var option_pointer := pointer + "/choice/options/" + str(index)
				if not option is Dictionary:
					return _fail("stories", option_pointer, "选项必须为对象")
				for key in option:
					if key not in ["text", "requires", "effects", "goto"]:
						return _fail("stories", option_pointer, "未知字段：" + str(key))
				if not option.get("text") is String or str(option.get("text", "")).strip_edges().is_empty():
					return _fail("stories", option_pointer + "/text", "选项缺少文字")
				if option.text in labels:
					return _fail("stories", option_pointer + "/text", "同一道选择里的文字不能重复")
				labels.append(option.text)
				var requirement: String = Rules.conditions_error(option.get("requires", []), bundle.flags, bundle.catalog)
				if not requirement.is_empty():
					return _fail("stories", option_pointer + "/requires", requirement)
				if (option.get("requires", []) as Array).is_empty(): fallback += 1
				var effect_error: String = Rules.effects_error(option.get("effects", {}), bundle.flags, bundle.catalog)
				if not effect_error.is_empty():
					return _fail("stories", option_pointer + "/effects", effect_error)
				if option.has("goto") and not _check_story_node(option.goto, option_pointer + "/goto", nodes):
					return false
			if fallback == 0:
				return _fail("stories", pointer + "/choice/options", "至少保留一个无条件选项，避免剧情无路可选")
			return true
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
		"scene":
			if not argument is String or not Scenes.has(argument):
				return _fail("stories", pointer + "/scene", "未知场景：" + str(argument))
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
