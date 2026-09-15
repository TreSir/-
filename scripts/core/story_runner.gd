extends Node
## Pure story flow: no UI or scene ownership. Waiting nodes are save checkpoints.

signal step_presented(step: Dictionary)
signal flow_error(message: String)

var story: Dictionary = {}
var variables: Dictionary = {}
var current_id := ""
var waiting := false
var source_path := ""

func load_story(path: String) -> String:
	var parser := JSON.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "无法读取剧情：" + path
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return "剧情 JSON 格式错误：" + parser.get_error_message()
	var data: Dictionary = parser.data
	var error := _validate(data)
	if not error.is_empty():
		return error
	story = data
	source_path = path
	return ""

func start() -> void:
	variables = story.get("defaults", {}).duplicate(true)
	_enter(story["start"])

func advance() -> void:
	if waiting and current_step().get("type") == "say":
		_enter(current_step()["next"])

func choose(index: int) -> void:
	if not waiting or current_step().get("type") != "choice":
		return
	var options: Array = current_step()["options"]
	if index < 0 or index >= options.size():
		return
	var option: Dictionary = options[index]
	if not matches(option.get("conditions", [])):
		return
	_apply(option.get("effects", {}))
	_enter(option["next"])

func complete_activity(result: Dictionary = {}) -> void:
	if not waiting or current_step().get("type") not in ["video", "minigame"]:
		return
	var step := current_step()
	var prefix: String = step.get("result_key", "activity")
	for key in result:
		variables[prefix + "." + str(key)] = result[key]
	_enter(step["next"])

func current_step() -> Dictionary:
	return story.get("nodes", {}).get(current_id, {})

func matches(conditions: Array) -> bool:
	for condition in conditions:
		var actual: Variant = variables.get(condition["var"])
		var expected: Variant = condition.get("value", true)
		match condition.get("op", "=="):
			"==":
				if actual != expected: return false
			"!=":
				if actual == expected: return false
			">=", ">", "<=", "<":
				if not _number(actual) or not _number(expected): return false
				match condition["op"]:
					">=":
						if actual < expected: return false
					">":
						if actual <= expected: return false
					"<=":
						if actual > expected: return false
					"<":
						if actual >= expected: return false
	return true

func snapshot() -> Dictionary:
	return {"story_id": story.get("id"), "story_version": story.get("version", 1),
		"node": current_id, "variables": variables.duplicate(true)}

func restore(data: Dictionary) -> String:
	if data.get("story_id") != story.get("id") or data.get("story_version") != story.get("version", 1):
		return "存档与当前剧情版本不匹配。"
	var node: Variant = data.get("node")
	if not node is String or not story["nodes"].has(node) or not data.get("variables") is Dictionary:
		return "存档内容不完整。"
	variables = story.get("defaults", {}).duplicate(true)
	variables.merge(data["variables"], true)
	_enter(node)
	return ""

func _enter(id: String) -> void:
	waiting = false
	# Bound automatic transitions so a malformed set/branch loop cannot freeze the game.
	for unused in range(128):
		current_id = id
		var step := current_step()
		match step.get("type"):
			"set":
				_apply(step.get("effects", {}))
				id = step["next"]
			"branch":
				id = step["then"] if matches(step["conditions"]) else step["else"]
			_:
				if step.get("type") == "choice":
					var available := false
					for option in step["options"]:
						available = available or matches(option.get("conditions", []))
					if not available:
						flow_error.emit("选项全部不可用：" + id)
						return
				waiting = true
				step_presented.emit(step.duplicate(true))
				return
	flow_error.emit("剧情自动跳转超过 128 次，请检查循环：" + current_id)

func _apply(effects: Dictionary) -> void:
	variables.merge(effects.get("set", {}), true)
	for key in effects.get("add", {}):
		var previous: Variant = variables.get(key, 0)
		if _number(previous):
			variables[key] = previous + effects["add"][key]

func _number(value: Variant) -> bool:
	return value is int or value is float

func _valid_conditions(value: Variant) -> bool:
	if not value is Array: return false
	for item in value:
		if not item is Dictionary or not item.get("var") is String: return false
		if item.get("op", "==") not in ["==", "!=", ">=", ">", "<=", "<"]: return false
	return true

func _valid_effects(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not value.get("set", {}) is Dictionary or not value.get("add", {}) is Dictionary: return false
	for amount in value.get("add", {}).values():
		if not _number(amount): return false
	return true

func _validate(data: Dictionary) -> String:
	if not data.get("id") is String or not data.get("nodes") is Dictionary or not data.get("defaults", {}) is Dictionary:
		return "剧情必须包含 id、nodes，defaults 必须为对象。"
	var nodes: Dictionary = data["nodes"]
	if not data.get("start") is String or not nodes.has(data["start"]): return "剧情起点不存在。"
	for id in nodes:
		var step: Variant = nodes[id]
		if not step is Dictionary: return "节点必须为对象：" + id
		var kind: String = str(step.get("type", ""))
		var targets: Array = []
		if kind not in ["say", "choice", "set", "branch", "video", "minigame", "ending"]:
			return "未知节点类型：" + id
		if kind in ["say", "set", "video", "minigame"]: targets.append(step.get("next"))
		if not _valid_effects(step.get("effects", {})): return "效果格式错误：" + id
		if kind == "branch":
			if not _valid_conditions(step.get("conditions")): return "条件格式错误：" + id
			targets.append_array([step.get("then"), step.get("else")])
		if kind == "choice":
			if not step.get("options") is Array or step["options"].is_empty(): return "缺少选项：" + id
			for option in step["options"]:
				if not option is Dictionary or not option.get("text") is String: return "选项格式错误：" + id
				if not _valid_conditions(option.get("conditions", [])) or not _valid_effects(option.get("effects", {})):
					return "选项条件或效果错误：" + id
				targets.append(option.get("next"))
		if kind == "minigame":
			if not step.get("scene") is String or not step.get("config", {}) is Dictionary: return "小游戏配置错误：" + id
		if kind == "video" and not step.get("path", "") is String: return "视频路径错误：" + id
		if kind in ["minigame", "video"] and not step.get("result_key", "activity") is String: return "结果前缀错误：" + id
		if kind == "ending" and not step.get("ending_id") is String: return "结局缺少 ending_id：" + id
		for target in targets:
			if not target is String or not nodes.has(target): return "节点 %s 指向不存在的节点：%s" % [id, target]
	return ""
