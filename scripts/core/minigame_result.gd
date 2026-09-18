extends RefCounted
## 小游戏结果的标准形状：`{type, score, data}`（设计文档 §10：不只有成功 / 失败）。
##
## **小游戏不决定剧情**（§9.3）：它只说「打成什么样」——剧情用 if 查
## `minigame.<id>.type` 决定给什么；调查结算用 `passed()` 决定让不让提交。
## 结果落进 GameState 的规矩在 investigation.note_minigame，这里只有词表与形状。

## 允许的结果类型。**data_loader 校验 minigame.*.type 的值表时直接读这张表**——
## 和 COMMANDS / ACTIONS 一个规矩：加类型只改这里一处。
const TYPES := ["perfect", "success", "partial", "failed", "cancelled"]

## 算「过」的类型：调查结算的门槛（允许重试的那条线）。
const PASSING := ["perfect", "success", "partial"]

static func passed(type: String) -> bool:
	return type in PASSING

## 把一个小游戏交回来的东西规范成标准形状。
##
## 只认标准形状 `{type, score, data?}`：没写 type、或拼错的名字，一律记 failed——
## 宁可当没打成，也不能让一个拼错的名字冒充成功。
static func normalize(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var type := str(source.get("type", ""))
	var raw_score: Variant = source.get("score", 0)
	var score: int = int(raw_score) if raw_score is float or raw_score is int else 0
	if not type in TYPES: type = "failed"
	var data: Variant = source.get("data", {})
	return {"type": type, "score": clampi(score, 0, 100), "data": data if data is Dictionary else {}}
