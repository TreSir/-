extends RefCounted
## One class per command. All commands return {status: goto|wait|error, ...}.
func command_name() -> String:
	return ""

func is_checkpoint() -> bool:
	return true

func validate(_context, _node: Dictionary) -> void:
	pass

func execute(_runtime, node: Dictionary) -> Dictionary:
	return {"status": "wait", "view": node.duplicate(true)}

func resume(_runtime, node: Dictionary, _input: Dictionary) -> Dictionary:
	return {"status": "goto", "target": node.get("next", "")}
