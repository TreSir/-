extends "res://scripts/core/command.gd"
## Extension example: a new command, no interpreter edits.
func command_name() -> String: return "emit"
func is_checkpoint() -> bool: return false
func validate(c, node: Dictionary) -> void:
	c.required(node, "event", TYPE_STRING)
	if node.has("payload") and not node.payload is Dictionary: c.problem("payload", "payload 必须是对象")
	c.target(node)
func execute(_runtime, node: Dictionary) -> Dictionary:
	EventBus.custom_event.emit(node.event, node.get("payload", {}).duplicate(true))
	return {"status": "goto", "target": node.next}
