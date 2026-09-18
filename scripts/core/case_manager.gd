extends RefCounted
## 案件管理器（设计文档 §15-17）：**不做多案件并行**——全部案件里最多一个「调查中」。
##
## 状态机只有三档，词表写死在代码里（数据只能照抄，不能自己发明）：
##   locked（未解锁）→ active（调查中）→ completed（已结案）
## 结果（result）是结案时写下的结论，词表来自案件自己的声明（cases.json 的 results）。
##
## 写在哪：状态与结果都是 GameState 的旗标（case.<id>.state / case.<id>.result）。
## 「最多一个 active」这条不变量挂在 Rules.snapshot_error 里——剧情 effect、
## 管理器的口子、读档，**任何写路径都绕不过那份体检**，不靠调用方自觉。
##
## 这里只放纯逻辑：不变量 + 当前案件的查询口。读给 UI / 结案用。

## 案件状态的词表。data_loader 校验 case.<id>.state 的 values 时读它——
## 加一档状态只改这里一处（和 MiniGameResult.TYPES / Runner.COMMANDS 一个规矩）。
const STATES := ["locked", "active", "completed"]

## 当前进行中的案件 id；没有就返回空串。这就是「0 或 1 个 Active Case」的查询口。
static func active_case(bundle: Dictionary, flags: Dictionary) -> String:
	for id in bundle.get("cases", {}):
		if str(flags.get("case." + str(id) + ".state", "locked")) == "active":
			return str(id)
	return ""

## 世界不变量：任何时刻最多一个进行中的案件（设计文档 §16）。
## 体检标准的一部分——存档校验 / game_state.restore / 每笔事务都过它，
## 于是「数据直接把第二个案件写成 active」也会被整笔拒绝，而不是悄悄并存。
static func snapshot_error(flags: Dictionary, definitions: Dictionary) -> String:
	var actives: Array = []
	for id in definitions:
		var key := str(id)
		if not key.begins_with("case.") or not key.ends_with(".state"): continue
		if str(flags.get(key, "")) == "active": actives.append(key)
	if actives.size() > 1: return "同时有多个进行中的案件：" + ", ".join(actives)
	return ""
