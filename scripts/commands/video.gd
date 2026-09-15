extends "res://scripts/core/activity_command.gd"
func command_name() -> String: return "video"
func validate(c, node: Dictionary) -> void:
	if c.required(node, "path", TYPE_STRING):
		if not node.path.is_empty() and not ResourceLoader.exists(node.path, "VideoStream"): c.problem("path", "视频资源不存在或类型错误")
	c.results(node)
	c.target(node)
