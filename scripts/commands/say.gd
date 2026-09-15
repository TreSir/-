extends "res://scripts/core/command.gd"
func command_name() -> String: return "say"
func validate(c, node: Dictionary) -> void:
	c.required(node, "text", TYPE_STRING)
	c.target(node)
