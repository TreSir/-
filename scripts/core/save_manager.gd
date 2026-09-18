extends RefCounted
## 存档的「形状」：怎么打包、怎么校验、怎么写盘读盘。**不持有状态，全是静态函数**——
## 「谁调它、什么时候能存」（行动锁、槽位名）是游戏规则，留在 investigation。
##
## 为什么抽出来：以前这些和「调查编排」混在一起；文档把 SaveManager 列为独立系统，
## 之后还要长检查点，所以先把「格式」这块切出来，让 investigation 回归「规则」。
const Store = preload("res://scripts/core/save_store.gd")
const Rules = preload("res://scripts/core/rules.gd")

## 存档格式版本 / 内容标识。对不上宁可拒绝，不猜。
## 内容标识在**状态含义变了**的时候要跟着走：这次把 case.<id>.status 换成了
## state / result 两件套、人物档案改成逐条解锁——旧存档的旗标已经不认了，
## 与其让它栽在「未声明 Flag」上，不如在这里干净地拒绝。
const SCHEMA := 1
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

static func write(slot: String, data: Dictionary) -> String:
	return Store.new().write(slot, data)

static func read(slot: String) -> Dictionary:
	return Store.new().read(slot)

## 抹掉一个槽位（新开一局时清检查点用）。槽位本来就空着不算失败。
static func erase(slot: String) -> String:
	return Store.new().erase(slot)
