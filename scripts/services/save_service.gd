extends Node
const Migrations = preload("res://scripts/services/save_migrations.gd")
var directory := "user://saves"
func save_slot(slot: String, data: Dictionary) -> String:
	if not _valid_slot(slot): return "存档槽名称无效"
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return "无法创建存档目录"
	var path := directory.path_join(slot + ".json")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "无法打开存档"
	file.store_string(JSON.stringify({"format": 2, "data": data}, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return "写入存档失败"
	if DirAccess.rename_absolute(temporary, path) != OK: return "替换存档失败"
	return ""
func load_slot(slot: String, bundle: Dictionary) -> Dictionary:
	if not _valid_slot(slot): return {"error": "存档槽名称无效"}
	var file := FileAccess.open(directory.path_join(slot + ".json"), FileAccess.READ)
	if file == null: return {"error": "还没有该存档"}
	var envelope: Variant = JSON.parse_string(file.get_as_text())
	if not envelope is Dictionary: return {"error": "存档 JSON 损坏"}
	return Migrations.new().migrate(envelope, bundle)
func _valid_slot(slot: String) -> bool:
	return not slot.is_empty() and slot.is_valid_identifier()
