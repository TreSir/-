extends Control
## Subclass this script; emit finish({...}) once. The host owns cleanup.
signal completed(result: Dictionary)

var _finished := false

func begin(_config: Dictionary, _story_variables: Dictionary) -> void:
	pass

func finish(result: Dictionary) -> void:
	if _finished: return
	_finished = true
	completed.emit(result)
