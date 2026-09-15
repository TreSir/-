extends RefCounted
const Command = preload("res://scripts/core/command.gd")
var commands: Dictionary = {}
var errors: Array[String] = []

func discover(directory: String = "res://scripts/commands") -> void:
	commands.clear()
	errors.clear()
	var folder := DirAccess.open(directory)
	if folder == null:
		errors.append(directory + ":1: 命令目录不存在")
		return
	var files := folder.get_files()
	files.sort()
	for filename in files:
		var source := filename.trim_suffix(".remap")
		if not source.ends_with(".gd"): continue
		var script = load(directory.path_join(source))
		if script == null:
			errors.append(directory.path_join(source) + ":1: 无法加载命令")
			continue
		register(script)

func register(script: Script) -> void:
	var command = script.new()
	if not command is Command or command.command_name().is_empty():
		errors.append(script.resource_path + ":1: 必须继承 Command 并声明名称")
		return
	var name: String = command.command_name()
	if commands.has(name):
		errors.append(script.resource_path + ":1: 命令名称重复：" + name)
		return
	commands[name] = command
