extends RefCounted
## 角色图鉴管理器（设计文档 §12-14）。
##
## 两份东西分得清楚：
##   CharacterData —— 角色**实际是什么**：codex.json 的条目（title / text），静态数据；
##   CharacterCodexState —— 玩家**目前知道什么**：GameState 的旗标——
##     · person.<id>.discovered    认识这个人没有（图鉴里有没有这张卡）
##     · person.<id>.info.<条目>   一条档案解锁没有
##     · person.<id>.codex_new     有没有未读的新条目（打开单人页清除）
##
## 图鉴**不是界面自己判断解锁**（§12.1）：解锁由剧情驱动（unlock / unlockinfo 指令、
## 线索与行动的 effects），界面只问这里「这个人现在看得见什么」。
##
## 这里是纯逻辑：读 + 校验；写状态一律走 investigation 的口子（铁律 1）。

## 这个人的条目表（顺序就是显示顺序）。
static func fields_of(bundle: Dictionary, id: String) -> Array:
	var entry: Variant = bundle.get("codex", {}).get(id, {})
	if not entry is Dictionary: return []
	return entry.get("fields", [])

## 解锁一条档案合不合法：人物在不在、条目在不在。
## 剧情数据（unlockinfo 指令）和 investigation 的口子共用这一份判断。
static func unlock_error(bundle: Dictionary, id: String, field: String) -> String:
	if not bundle.get("people", {}).has(id): return "未知人物：" + id
	if not bundle.get("codex", {}).has(id): return "没有这个人的图鉴：" + id
	for item in fields_of(bundle, id):
		if str(item.get("id", "")) == field: return ""
	return "未知档案条目：%s.%s" % [id, field]

## 这个人现在看得见的档案：[{id, title, text, unlocked}]。
## unlocked 读的是状态旗标——界面照这个画，不自己推导解锁规则。
static func rows(bundle: Dictionary, flags: Dictionary, id: String) -> Array:
	var out: Array = []
	for item in fields_of(bundle, id):
		var field := str(item.get("id", ""))
		out.append({
			"id": field,
			"title": str(item.get("title", "")),
			"text": str(item.get("text", "")),
			"unlocked": bool(flags.get("person." + id + ".info." + field, false)),
		})
	return out

## 一次状态变化里「哪些人的图鉴翻开了新页」：新认识的人、或新解锁的条目。
##
## 剧情 effects 写状态后由 investigation 调它补 codex_new——这样无论解锁走哪条
## 来路（口子 / 线索效果 / 行动效果 / 事件效果），「有新内容」都不会漏。
static func touched(before: Dictionary, after: Dictionary) -> Array:
	var names: Array = []
	for key in after:
		var id := str(key)
		if not id.begins_with("person."): continue
		# 只有**解锁旗标**（bool 且翻成 true）算「翻开了新页」：
		# person.* 下还有 identity / truth 这类数值，它们走过不该点小红点。
		if not after[key] is bool or after[key] != true: continue
		if before.get(key, false) == true: continue
		var cut := -1
		if id.ends_with(".discovered"):
			cut = id.rfind(".discovered")
		elif id.contains(".info."):
			cut = id.find(".info.")
		if cut <= 7: continue
		var person := id.substr(7, cut - 7)
		if not person in names: names.append(person)
	return names
