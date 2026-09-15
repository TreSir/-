extends "res://scripts/core/command.gd"
func resume(runtime, node: Dictionary, input: Dictionary) -> Dictionary:
	var result: Dictionary = input.get("result", {})
	var values: Dictionary = {}
	for key in node.get("result_map", {}):
		var flag: String = node.result_map[key]
		values[flag] = result.get(key, GameState.definitions[flag]["default"])
	var error: String = GameState.apply({"set": values})
	if not error.is_empty(): return {"status": "error", "message": error}
	return {"status": "goto", "target": node.next}
