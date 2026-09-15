extends "res://scripts/core/minigame.gd"
## Example only: collect signals; replace this scene with your actual minigame.

var hits := 0
var target := 3

func begin(config: Dictionary, _story_variables: Dictionary) -> void:
	target = maxi(1, int(config.get("target", 3)))
	$Panel/Rows/Collect.pressed.connect(_collect)
	$Panel/Rows/GiveUp.pressed.connect(func(): finish({"success": false, "score": hits}))
	_refresh()

func _collect() -> void:
	hits += 1
	_refresh()
	if hits >= target: finish({"success": true, "score": hits})

func _refresh() -> void:
	$Panel/Rows/Progress.text = "已收集信号 %d / %d" % [hits, target]
