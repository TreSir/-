extends "res://scripts/core/command.gd"
func command_name() -> String: return "jump"
func is_checkpoint() -> bool: return false
func validate(c, node: Dictionary) -> void: c.target(node)
func execute(_runtime, node: Dictionary) -> Dictionary:
	return {"status": "goto", "target": node.next}
