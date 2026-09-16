extends Control
## 小游戏基类。子类自己 emit 一次 finish({...})；弹层与清理由宿主负责。
signal completed(result: Dictionary)

var _finished := false

func begin(_config: Dictionary, _story_variables: Dictionary) -> void:
	pass

func finish(result: Dictionary) -> void:
	if _finished: return
	_finished = true
	completed.emit(result)
