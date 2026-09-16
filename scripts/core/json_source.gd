extends RefCounted
## JSON 前端 + source map：JSON 管语法，这里把每个值映射回行号，好报「哪个文件哪一行错了」。
var data: Variant
var locations: Dictionary = {}
var error := ""
var path := ""
var _text := ""
var _offset := 0
var _line := 1

func read_file(file_path: String) -> void:
	path = file_path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "%s:1: 无法读取文件" % path
		return
	parse_text(file.get_as_text(), path)

func parse_text(text: String, file_path: String = "<memory>") -> void:
	path = file_path
	_text = text
	_offset = 0
	_line = 1
	error = ""
	locations.clear()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		error = "%s:%d: %s" % [path, parser.get_error_line() + 1, parser.get_error_message()]
		return
	data = parser.data
	_walk("")

func diagnostic(pointer: String, message: String) -> String:
	var lookup := pointer
	while not locations.has(lookup) and not lookup.is_empty():
		lookup = lookup.left(lookup.rfind("/"))
	return "%s:%d: %s" % [path, locations.get(lookup, 1), message]

func _space() -> void:
	while _offset < _text.length() and _text[_offset] in [" ", "\t", "\r", "\n"]:
		if _text[_offset] == "\n": _line += 1
		_offset += 1

func _string() -> String:
	var start := _offset
	_offset += 1
	while _offset < _text.length():
		if _text[_offset] == "\\":
			_offset += 2
		elif _text[_offset] == '"':
			_offset += 1
			break
		else:
			_offset += 1
	return str(JSON.parse_string(_text.substr(start, _offset - start)))

func _walk(pointer: String) -> void:
	_space()
	locations[pointer] = _line
	var token := _text[_offset]
	if token == "{":
		_offset += 1
		_space()
		var seen: Dictionary = {}
		while _text[_offset] != "}":
			var key_line := _line
			var key := _string()
			if seen.has(key): error = "%s:%d: 重复 JSON 键：%s" % [path, key_line, key]
			seen[key] = true
			_space()
			_offset += 1
			_walk(pointer + "/" + key)
			_space()
			if _text[_offset] != ",": break
			_offset += 1
			_space()
		_offset += 1
	elif token == "[":
		_offset += 1
		_space()
		var index := 0
		while _text[_offset] != "]":
			_walk(pointer + "/" + str(index))
			index += 1
			_space()
			if _text[_offset] != ",": break
			_offset += 1
		_offset += 1
	elif token == '"':
		_string()
	else:
		while _offset < _text.length() and _text[_offset] not in [",", "}", "]", " ", "\n", "\r", "\t"]:
			_offset += 1
