extends RefCounted
## 纯函数式的旗标规则求值。data_loader / investigation / game_state 共用同一套，不重复实现。
## 单活动案件这类**世界不变量**也收在这里：一体检就全查，写路径绕不过去。
const CaseManager = preload("res://scripts/core/case_manager.gd")

static func number(value: Variant) -> bool:
	return value is int or value is float

static func integer(value: Variant) -> bool:
	return number(value) and is_finite(float(value)) and value == floor(value)

static func value_error(value: Variant, definition: Dictionary) -> String:
	match definition.get("type"):
		"bool":
			if not value is bool: return "应为 bool"
		"int":
			if not integer(value): return "应为 int"
		"float":
			if not number(value) or not is_finite(float(value)): return "应为有限数值"
		"string":
			if not value is String: return "应为 string"
		_:
			return "未知 Flag 类型"
	if number(value):
		if definition.has("min") and value < definition.min: return "低于最小值"
		if definition.has("max") and value > definition.max: return "超过最大值"
	if definition.has("values") and not value in definition["values"]: return "不在允许值中"
	return ""

## 一整份状态快照的体检：旗标都在声明里、值都合法、道具数量在范围内。
##
## 放在这里而不是 GameState 里：这是**纯规则求值**（只吃 definitions / catalog），
## 不碰任何持有中的状态。存档校验（save_manager）和还原（game_state.restore）
## 因此共用同一份体检标准，也只写一次。
static func snapshot_error(snapshot: Dictionary, definitions: Dictionary, catalog: Dictionary) -> String:
	if not snapshot.get("flags") is Dictionary or not snapshot.get("inventory") is Dictionary: return "状态快照格式错误"
	for id in snapshot.flags:
		if not definitions.has(id): return "存档有未声明 Flag：" + str(id)
		var error: String = value_error(snapshot.flags[id], definitions[id])
		if not error.is_empty(): return str(id) + "：" + error
	for id in snapshot.inventory:
		if not catalog.get("items", {}).has(id): return "存档有未知道具：" + str(id)
		var count: Variant = snapshot.inventory[id]
		if not integer(count) or count <= 0 or count > catalog.items[id].get("max_stack", 99): return "非法道具数量：" + str(id)
	# 世界不变量（最多一个进行中的案件）也在这里：所有写路径共用的同一份体检。
	return CaseManager.snapshot_error(snapshot.flags, definitions)

static func effects_error(effects: Variant, definitions: Dictionary, catalog: Dictionary) -> String:
	if not effects is Dictionary: return "effects 必须为对象"
	for field in effects:
		if field not in ["set", "add", "inventory"]: return "未知效果字段：" + str(field)
	for field in ["set", "add", "inventory"]:
		if not effects.get(field, {}) is Dictionary: return field + " 必须为对象"
	for id in effects.get("set", {}):
		if not definitions.has(id): return "未知 Flag：" + str(id)
		var error := value_error(effects.set[id], definitions[id])
		if not error.is_empty(): return str(id) + "：" + error
	for id in effects.get("add", {}):
		if not definitions.has(id): return "未知 Flag：" + str(id)
		var type: String = definitions[id].get("type", "")
		if type not in ["int", "float"] or not number(effects.add[id]): return "add 只支持数值 Flag：" + str(id)
		if type == "int" and not integer(effects.add[id]): return "int 增量必须为整数：" + str(id)
	for id in effects.get("inventory", {}):
		if not catalog.get("items", {}).has(id): return "未知道具：" + str(id)
		if not integer(effects.inventory[id]): return "道具增减必须为整数：" + str(id)
	return ""

static func conditions_error(conditions: Variant, definitions: Dictionary, catalog: Dictionary) -> String:
	if not conditions is Array: return "conditions 必须为数组"
	for condition in conditions:
		if not condition is Dictionary: return "条件必须为对象"
		if condition.has("flag") == condition.has("item"): return "条件必须指定 flag 或 item 中的一种"
		for key in condition:
			if key not in ["flag", "item", "op", "value"]: return "未知条件字段：" + str(key)
		var definition: Dictionary
		if condition.has("flag"):
			if not definitions.has(condition.flag): return "未知 Flag：" + str(condition.flag)
			definition = definitions[condition.flag]
		else:
			if not catalog.get("items", {}).has(condition.item): return "未知道具：" + str(condition.item)
			definition = {"type": "int", "min": 0}
		var value: Variant = condition.get("value", true)
		var error := value_error(value, definition)
		if not error.is_empty(): return "条件值" + error
		var op: String = str(condition.get("op", "=="))
		if op not in ["==", "!=", ">=", ">", "<=", "<"]: return "未知比较操作符：" + op
		if op not in ["==", "!="] and definition.get("type") not in ["int", "float"]: return "大小比较只支持数值"
	return ""

static func matches(conditions: Array, flags: Dictionary, inventory: Dictionary) -> bool:
	for condition in conditions:
		var actual: Variant = flags.get(condition.get("flag")) if condition.has("flag") else inventory.get(condition.item, 0)
		var expected: Variant = condition.get("value", true)
		match condition.get("op", "=="):
			"==":
				if actual != expected: return false
			"!=":
				if actual == expected: return false
			">=":
				if actual < expected: return false
			">":
				if actual <= expected: return false
			"<=":
				if actual > expected: return false
			"<":
				if actual >= expected: return false
	return true
