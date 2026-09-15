extends "res://scripts/core/command.gd"
func command_name() -> String: return "ending"
func execute(runtime, _node: Dictionary) -> Dictionary:
	for ending in runtime.bundle.endings:
		if runtime.matches(ending.conditions):
			var view: Dictionary = ending.duplicate(true)
			view["op"] = "ending"
			view["ending_id"] = ending.id
			if not runtime.debug_preview:
				EventBus.ending_reached.emit(ending.id, ending.get("entry", ""))
			return {"status": "wait", "view": view}
	return {"status": "error", "message": "没有匹配的结局"}
func resume(runtime, _node: Dictionary, _input: Dictionary) -> Dictionary:
	runtime.restart_requested.emit()
	return {"status": "hold"}
