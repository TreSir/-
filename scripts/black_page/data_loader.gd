extends RefCounted
## Compile investigation content onto the existing typed flags / inventory rules.
const Source = preload("res://scripts/core/json_source.gd")
const Rules = preload("res://scripts/core/rules.gd")
var sources: Dictionary = {}
var error := ""

func compile(directory: String = "res://data/black_page") -> Dictionary:
	sources.clear()
	error = ""
	var result: Dictionary = {"id": "black_page", "catalog": {"items": {}, "entries": {}}}
	for name in ["flags", "people", "clues", "actions", "cases", "events", "endings", "codex", "transitions", "opening"]:
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
	for id in result.flags:
		var definition: Variant = result.flags[id]
		if not definition is Dictionary or not definition.has("default"):
			_fail("flags", "/" + id, "缺少类型或默认值")
			return {}
		var message: String = Rules.value_error(definition.default, definition)
		if not message.is_empty():
			_fail("flags", "/" + id, message)
			return {}
	for id in {"day": "int", "actions_left": "int", "writes": "int", "wrong_writes": "int", "erosion": "int", "decision": "string", "ending": "string"}:
		var expected: String = "string" if id in ["decision", "ending"] else "int"
		if not result.flags.has(id) or result.flags[id].get("type") != expected:
			_fail("flags", "/" + id, "缺少或修改了结算核心 Flag 类型：" + id)
			return {}
	if result.flags.actions_left.default != 3 or result.flags.day.default != 1:
		_fail("flags", "", "本切片采用第1天开始、每日3次行动")
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
			for field in ["identity", "truth", "status", "discovered"]:
				if not bundle.flags.has("person." + id + "." + field): return _fail(group, pointer, "缺少人物状态声明 " + field)
		"clues":
			if not row.get("description") is String or not row.get("type") is String or not row.get("people") is Array:
				return _fail(group, pointer, "缺少线索描述、类型或人物列表")
			for person in row.people:
				if not bundle.people.has(person): return _fail(group, pointer + "/people", "未知人物")
			if not bundle.flags.has("clue." + id + ".reliability"): return _fail(group, pointer, "缺少可信度声明")
		"actions":
			if row.get("kind") not in ["dialogue", "document", "minigame"] or not row.get("text") is String or not row.get("clues") is Array:
				return _fail(group, pointer, "调查类型、正文或奖励格式错误")
			if not bundle.flags.has("action." + id + ".done"): return _fail(group, pointer, "缺少完成状态声明")
			for clue in row.clues:
				if not bundle.clues.has(clue): return _fail(group, pointer + "/clues", "未知线索 " + str(clue))
			if row.kind == "minigame":
				if not row.get("scene") is String or not ResourceLoader.exists(row.scene): return _fail(group, pointer + "/scene", "小游戏场景不存在")
				if not row.get("config") is Dictionary: return _fail(group, pointer, "小游戏缺少参数")
		"events":
			if not row.get("text") is String or not bundle.flags.has("event." + id + ".done"): return _fail(group, pointer, "事件缺少文本或完成声明")
		"cases":
			if not row.get("intro") is String or not row.get("questions") is Array: return _fail(group, pointer, "案件缺少介绍或疑点")
			if not bundle.flags.has("case." + id + ".status"): return _fail(group, pointer, "缺少案件状态声明")
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

func _fail(group: String, pointer: String, message: String) -> bool:
	error = sources[group].diagnostic(pointer, message)
	return false
