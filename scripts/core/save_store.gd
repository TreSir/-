extends RefCounted
## 存档文件的读写。只管进度本身，不碰别的层。

const DIRECTORY := "user://saves"
const FORMAT_VERSION := 1

func write(name: String, data: Dictionary, backup_existing := true) -> String:
	var error := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error != OK: return "无法创建存档目录。"
	var path := DIRECTORY.path_join(name + ".json")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "无法写入存档。"
	file.store_string(JSON.stringify({"format": FORMAT_VERSION, "data": data}, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return "存档写入失败。"
	# 新文件写好后，才把封装可读取的旧文件留成备份。世界状态校验由调用方负责。
	if backup_existing and FileAccess.file_exists(path) and not _read_path(path).has("error"):
		error = DirAccess.copy_absolute(path, path + ".bak")
		if error != OK: return "无法备份旧存档。"
	error = DirAccess.rename_absolute(temporary, path)
	return "" if error == OK else "无法替换存档文件。"

func erase(name: String) -> String:
	var path := DIRECTORY.path_join(name + ".json")
	for target in [path + ".bak", path]:
		if not FileAccess.file_exists(target): continue
		var error := DirAccess.remove_absolute(target)
		if error != OK: return "无法删除存档文件。"
	return ""

func read(name: String) -> Dictionary:
	var path := DIRECTORY.path_join(name + ".json")
	return _read_path(path)

func read_backup(name: String) -> Dictionary:
	var path := DIRECTORY.path_join(name + ".json.bak")
	return _read_path(path)

func _read_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"error": "还没有存档。"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "无法读取存档。"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: return {"error": "存档损坏或格式版本不兼容。"}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or parsed.get("format") != FORMAT_VERSION or not parsed.get("data") is Dictionary:
		return {"error": "存档损坏或格式版本不兼容。"}
	return {"data": parsed["data"]}
