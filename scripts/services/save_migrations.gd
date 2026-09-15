extends RefCounted
const Rules = preload("res://scripts/core/rules.gd")
## Explicit, ordered migrations. Add a case and function for each story revision.
func migrate(envelope: Dictionary, bundle: Dictionary) -> Dictionary:
	if not Rules.integer(envelope.get("format")): return {"error": "存档格式版本必须为整数"}
	var format: int = int(envelope.get("format", 0))
	if format not in [1, 2] or not envelope.get("data") is Dictionary:
		return {"error": "无法识别存档格式"}
	var data: Dictionary = envelope.data.duplicate(true)
	if format == 1:
		data = {"story_id": data.get("story_id"), "story_version": data.get("story_version", 1),
			"cursor": data.get("node", ""), "state": {"flags": data.get("variables", {}), "inventory": data.get("inventory", {})},
			"locale": "zh_CN"}
	if data.get("story_id") != bundle.id: return {"error": "存档属于另一部剧情"}
	if not Rules.integer(data.get("story_version")): return {"error": "剧情版本必须为整数"}
	var version: int = int(data.get("story_version", 0))
	if version > int(bundle.version): return {"error": "存档来自更新版本的游戏"}
	while version < int(bundle.version):
		match version:
			1: data = _v1_to_v2(data, bundle)
			_: return {"error": "缺少从剧情版本 %d 开始的迁移函数" % version}
		version += 1
		data["story_version"] = version
	return {"data": data}
func _v1_to_v2(data: Dictionary, bundle: Dictionary) -> Dictionary:
	data["cursor"] = bundle.get("node_aliases", {}).get(data.get("cursor", ""), data.get("cursor", ""))
	return data
