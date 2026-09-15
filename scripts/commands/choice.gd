extends "res://scripts/core/command.gd"
func command_name() -> String: return "choice"
func validate(c, node: Dictionary) -> void:
	if not c.required(node, "options", TYPE_ARRAY): return
	if node.options.is_empty(): c.problem("options", "选项不能为空")
	for index in node.options.size():
		var option: Variant = node.options[index]
		var path := "options/%d/" % index
		if not option is Dictionary:
			c.problem(path, "选项必须为对象")
			continue
		c.text(option.get("text"), path + "text")
		c.target(option, "next", path)
		c.conditions(option.get("conditions", []), path + "conditions")
		c.effects(option.get("effects", {}), path + "effects")

func execute(runtime, node: Dictionary) -> Dictionary:
	var view := node.duplicate(true)
	view.options = []
	for index in node.options.size():
		if runtime.matches(node.options[index].get("conditions", [])):
			var option: Dictionary = node.options[index].duplicate(true)
			option["index"] = index
			view.options.append(option)
	if view.options.is_empty(): return {"status": "error", "message": "当前没有可用选项"}
	return {"status": "wait", "view": view}

func resume(runtime, node: Dictionary, input: Dictionary) -> Dictionary:
	var index: int = int(input.get("choice", -1))
	if index < 0 or index >= node.options.size(): return execute(runtime, node)
	var option: Dictionary = node.options[index]
	if not runtime.matches(option.get("conditions", [])): return execute(runtime, node)
	var error: String = GameState.apply(option.get("effects", {}))
	if not error.is_empty(): return {"status": "error", "message": error}
	return {"status": "goto", "target": option.next}
