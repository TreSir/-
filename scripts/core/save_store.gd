extends RefCounted
## 存档文件的读写。只管进度本身，不碰别的层。

const DIRECTORY := "user://saves"
const FORMAT_VERSION := 1

func write(name: String, data: Dictionary) -> String:
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
	error = DirAccess.rename_absolute(temporary, path)
	return "" if error == OK else "无法替换存档文件。"

func read(name: String) -> Dictionary:
	var path := DIRECTORY.path_join(name + ".json")
	if not FileAccess.file_exists(path): return {"error": "还没有存档。"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "无法读取存档。"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("format") != FORMAT_VERSION or not parsed.get("data") is Dictionary:
		return {"error": "存档损坏或格式版本不兼容。"}
	return {"data": parsed["data"]}
