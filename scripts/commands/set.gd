extends "res://scripts/core/command.gd"
func command_name() -> String: return "set"
func is_checkpoint() -> bool: return false
func validate(c, node: Dictionary) -> void:
	c.effects(node.get("effects", {}))
	c.target(node)
func execute(_runtime, node: Dictionary) -> Dictionary:
	var error: String = GameState.apply(node.get("effects", {}))
	if not error.is_empty(): return {"status": "error", "message": error}
	return {"status": "goto", "target": node.next}
