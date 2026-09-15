extends RefCounted
const Rules = preload("res://scripts/core/rules.gd")
var bundle: Dictionary
var source
var pointer := ""
var chapter := ""
var errors: Array = []

func problem(field: String, message: String) -> void:
	errors.append(source.diagnostic(pointer + ("/" + field if not field.is_empty() else ""), message))

func required(node: Dictionary, field: String, type: int) -> bool:
	if not node.has(field) or typeof(node[field]) != type:
		problem(field, "缺少字段或字段类型错误：" + field)
		return false
	return true

func target(node: Dictionary, key: String = "next", prefix: String = "") -> void:
	if not node.get(key) is String:
		problem(prefix + key, "缺少跳转目标：" + key)
		return
	var id: String = node[key]
	if not id.contains("."): id = chapter + "." + id
	if not bundle.nodes.has(id): problem(prefix + key, "不存在的节点：" + id)
	node[key] = id

func effects(value: Variant, field: String = "effects") -> void:
	var error: String = Rules.effects_error(value, bundle.flags, bundle.catalog)
	if not error.is_empty():
		# Point undeclared keys at their actual JSON value, including nested effects.
		var precise := field
		if value is Dictionary:
			for group in ["set", "add", "inventory"]:
				if not value.get(group, {}) is Dictionary: continue
				for id in value.get(group, {}):
					if error.contains(str(id)): precise = field + "/" + group + "/" + str(id)
		problem(precise, error)

func conditions(value: Variant, field: String = "conditions") -> void:
	var error: String = Rules.conditions_error(value, bundle.flags, bundle.catalog)
	if not error.is_empty():
		var precise := field
		if value is Array:
			for index in value.size():
				if value[index] is Dictionary:
					for key in ["flag", "item"]:
						if value[index].has(key) and error.contains(str(value[index][key])):
							precise = field + "/" + str(index) + "/" + key
		problem(precise, error)

func text(value: Variant, field: String) -> void:
	if not value is String:
		problem(field, "文本必须为字符串")
	elif value.begins_with("@") and not bundle.locales.get("zh_CN", {}).has(value.substr(1)):
		problem(field, "缺少本地化文本：" + value)

func results(node: Dictionary) -> void:
	if not node.get("result_map", {}) is Dictionary:
		problem("result_map", "结果映射必须为对象")
		return
	for key in node.get("result_map", {}):
		if not bundle.flags.has(node.result_map[key]): problem("result_map/" + key, "未声明结果 Flag：" + str(node.result_map[key]))
