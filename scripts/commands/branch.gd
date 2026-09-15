extends "res://scripts/core/command.gd"
func command_name() -> String: return "branch"
func is_checkpoint() -> bool: return false
func validate(c, node: Dictionary) -> void:
	c.conditions(node.get("conditions"))
	c.target(node, "then")
	c.target(node, "else")
func execute(runtime, node: Dictionary) -> Dictionary:
	return {"status": "goto", "target": node.then if runtime.matches(node.conditions) else node["else"]}
