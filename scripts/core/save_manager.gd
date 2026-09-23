extends RefCounted
## 存档的「形状」：怎么打包、怎么校验、怎么写盘读盘。**不持有状态，全是静态函数**——
## 「谁调它、什么时候能存」（行动锁、槽位名）是游戏规则，留在 investigation。
##
## 为什么抽出来：以前这些和「调查编排」混在一起；文档把 SaveManager 列为独立系统，
## 之后还要长检查点，所以先把「格式」这块切出来，让 investigation 回归「规则」。
const Store = preload("res://scripts/core/save_store.gd")
const Rules = preload("res://scripts/core/rules.gd")

## schema 2 保持现有内容标识；schema 1 的相同内容可无损升级。
## 内容标识不同代表状态含义可能变化，不能只改版本号强行兼容。
const SCHEMA := 2
const CONTENT := "black_page_mvp2"
## 日志最多留这么多条——超了丢最旧的。写入和校验共用同一个数。
const JOURNAL_CAP := 100

static func payload(state: Dictionary, pending: Array, journal: Array) -> Dictionary:
	return {
		"schema": SCHEMA,
		"content": CONTENT,
		"state": state,
		"pending": pending.duplicate(true),
		"journal": journal.duplicate(),
	}

## 迁移只在内存里进行，读取失败或校验失败时绝不触碰磁盘上的原文件。
## 新增 schema 时在这里串接显式的逐版本迁移函数。
static func migrate(data: Dictionary) -> Dictionary:
	if data.get("content") != CONTENT: return {"error": "存档版本或游戏不匹配。"}
	var version: Variant = data.get("schema")
	if not Rules.integer(version) or int(version) < 1 or int(version) > SCHEMA:
		return {"error": "存档版本或游戏不匹配。"}
	var candidate := data.duplicate(true)
	while int(candidate.schema) < SCHEMA:
		match int(candidate.schema):
			1: candidate = _migrate_v1_to_v2(candidate)
			_: return {"error": "缺少存档迁移规则。"}
	return {"data": candidate, "migrated": int(version) != SCHEMA}

static func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	# 两版的状态字段相同；提升格式版本后仍须通过完整世界状态校验。
	var result := data.duplicate(true)
	result.schema = 2
	return result

static func prepare(data: Dictionary, definitions: Dictionary, catalog: Dictionary, content: Dictionary = {}) -> Dictionary:
	var result := migrate(data)
	if result.has("error"): return result
	var error := validate(result.data, definitions, catalog, content)
	if not error.is_empty(): return {"error": error}
	return result

## 存档结构 + 世界状态 + 落笔记录的完整校验。返回空串才算「能续」。
## 任何一处不对都拒绝整份存档，不做「修一半继续用」。
##
## 体检状态那一步在 Rules.snapshot_error：和 game_state.restore 共用同一份标准，
## 存档模块因此不用碰 GameState（写状态的口子全项目只有 investigation 一个）。
static func validate(data: Dictionary, definitions: Dictionary, catalog: Dictionary, content: Dictionary = {}) -> String:
	if data.get("schema") != SCHEMA or data.get("content") != CONTENT: return "存档版本或游戏不匹配。"
	if not data.get("state") is Dictionary or not data.get("pending") is Array or not data.get("journal") is Array: return "存档结构损坏。"
	var error: String = Rules.snapshot_error(data.state, definitions, catalog)
	if not error.is_empty(): return error
	var restored: Dictionary = {}
	for id in definitions: restored[id] = definitions[id].default
	restored.merge(data.state.flags, true)
	if not str(restored.ending).is_empty():
		var found := false
		for ending in content.get("endings", []):
			if ending.id == restored.ending: found = true
		if not found: return "结局 ID 已不存在。"
	if data.pending.size() > (content.get("people", {}) as Dictionary).size() or data.journal.size() > JOURNAL_CAP:
		return "存档记录数量异常。"
	var seen: Array = []
	for entry in data.pending:
		if not entry is Dictionary or not content.get("people", {}).has(entry.get("person")) or not entry.get("valid") is bool or not entry.get("name") is String or not Rules.integer(entry.get("day")): return "落笔记录损坏。"
		if entry.person in seen or entry.day != restored.day or restored["person." + entry.person + ".status"] == "dead" or restored.ending != "": return "落笔记录与世界状态冲突。"
		seen.append(entry.person)
	for message in data.journal:
		if not message is String: return "日志格式错误。"
	return ""

static func write(slot: String, data: Dictionary, backup_existing := true) -> String:
	return Store.new().write(slot, data, backup_existing)

static func read(slot: String) -> Dictionary:
	return Store.new().read(slot)

## 普通存档可从上一次有效备份恢复；检查点不走此路径，避免退到更早的一笔。
static func load_validated(slot: String, definitions: Dictionary, catalog: Dictionary, content: Dictionary = {}, use_backup := false) -> Dictionary:
	var primary := read(slot)
	if not primary.has("error"):
		# 明确属于另一内容版本或未来 schema 的文件不是损坏档；不能悄悄降级读旧备份。
		var stored: Dictionary = primary.data
		if stored.has("content") and stored.content != CONTENT: return {"error": "存档版本或游戏不匹配。"}
		var version: Variant = stored.get("schema")
		if Rules.integer(version) and (int(version) < 1 or int(version) > SCHEMA):
			return {"error": "存档版本或游戏不匹配。"}
		primary = prepare(primary.data, definitions, catalog, content)
		if not primary.has("error"): return primary
	if use_backup:
		var backup := Store.new().read_backup(slot)
		if not backup.has("error"):
			backup = prepare(backup.data, definitions, catalog, content)
			if not backup.has("error"):
				backup["recovered"] = true
				return backup
	return primary

## 抹掉一个槽位（新开一局时清检查点用）。槽位本来就空着不算失败。
static func erase(slot: String) -> String:
	return Store.new().erase(slot)
