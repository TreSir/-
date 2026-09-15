extends "res://scripts/core/activity_command.gd"
const Minigame = preload("res://scripts/core/minigame.gd")
func command_name() -> String: return "minigame"
func validate(c, node: Dictionary) -> void:
	if c.required(node, "scene", TYPE_STRING):
		if not ResourceLoader.exists(node.scene, "PackedScene"): c.problem("scene", "小游戏场景不存在")
	if node.has("config") and not node.config is Dictionary: c.problem("config", "小游戏 config 必须是对象")
	c.results(node)
	c.target(node)
