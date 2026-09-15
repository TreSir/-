extends RefCounted
## Frontends compile into this canonical AST. Add a DSL frontend later, reuse validation/runtime.
const Source = preload("res://scripts/core/json_source.gd")
const Context = preload("res://scripts/core/validation_context.gd")
const Rules = preload("res://scripts/core/rules.gd")
var errors: Array = []
var sources: Dictionary = {}

func _read(path: String, expected: int) -> Variant:
	var source = Source.new()
	source.read_file(path)
	sources[path] = source
	if not source.error.is_empty():
		errors.append(source.error)
		return {} if expected == TYPE_DICTIONARY else []
	if typeof(source.data) != expected:
		errors.append(source.diagnostic("", "文件顶层类型错误"))
		return {} if expected == TYPE_DICTIONARY else []
	return source.data

func compile(path: String, registry) -> Dictionary:
	errors.clear()
	sources.clear()
	var manifest: Dictionary = _read(path, TYPE_DICTIONARY)
	if not errors.is_empty(): return _result({})
	for field in ["id", "start", "flags", "characters", "endings", "catalog", "locales"]:
		if not manifest.get(field) is String: errors.append(sources[path].diagnostic("/" + field, "缺少字符串字段：" + field))
	if not manifest.get("chapters") is Array or not Rules.integer(manifest.get("version", 0)):
		errors.append(sources[path].diagnostic("", "缺少 chapters 或整数 version"))
	if not manifest.get("node_aliases", {}) is Dictionary:
		errors.append(sources[path].diagnostic("/node_aliases", "节点迁移映射必须是对象"))
	if not errors.is_empty(): return _result({})
	var bundle: Dictionary = manifest.duplicate(true)
	bundle["ast_version"] = 1
	bundle["nodes"] = {}
	for field in ["flags", "characters", "catalog", "locales"]:
		bundle[field] = _read(manifest[field], TYPE_DICTIONARY)
	bundle["endings"] = _read(manifest.endings, TYPE_ARRAY)
	for chapter_path in manifest.chapters:
		if not chapter_path is String:
			errors.append(sources[path].diagnostic("/chapters", "章节路径必须是字符串"))
			continue
		var chapter: Dictionary = _read(chapter_path, TYPE_DICTIONARY)
		if not chapter.get("id") is String or not chapter.get("nodes") is Array:
			errors.append(sources[chapter_path].diagnostic("", "章节需要 id 和 nodes 数组"))
			continue
		for index in chapter.nodes.size():
			var node: Variant = chapter.nodes[index]
			var pointer := "/nodes/" + str(index)
			if not node is Dictionary or not node.get("id") is String or not node.get("op") is String:
				errors.append(sources[chapter_path].diagnostic(pointer, "节点需要 id 与 op 字符串"))
				continue
			var id: String = chapter.id + "." + node.id
			if bundle.nodes.has(id):
				errors.append(sources[chapter_path].diagnostic(pointer + "/id", "重复节点：" + id))
				continue
			node = node.duplicate(true)
			node["id"] = id
			node["_source"] = {"file": chapter_path, "pointer": pointer, "chapter": chapter.id,
				"line": sources[chapter_path].locations.get(pointer, 1)}
			bundle.nodes[id] = node
	if not errors.is_empty(): return _result({})
	_validate_definitions(bundle, manifest)
	if not errors.is_empty(): return _result({})
	if not bundle.nodes.has(bundle.start): errors.append(sources[path].diagnostic("/start", "起点不存在"))
	for old_id in bundle.get("node_aliases", {}):
		if not bundle.nodes.has(bundle.node_aliases[old_id]):
			errors.append(sources[path].diagnostic("/node_aliases/" + old_id, "迁移目标节点不存在"))
	for id in bundle.nodes:
		var node: Dictionary = bundle.nodes[id]
		var context = Context.new()
		context.bundle = bundle
		context.source = sources[node._source.file]
		context.pointer = node._source.pointer
		context.chapter = node._source.chapter
		if not registry.commands.has(node.op):
			context.problem("op", "未注册的命令：" + node.op)
		else:
			for field in ["text", "title"]:
				if node.has(field): context.text(node[field], field)
			if node.has("speaker") and not bundle.characters.has(node.speaker): context.problem("speaker", "未知角色：" + str(node.speaker))
			for field in ["background", "portrait"]:
				if node.has(field) and (not node[field] is String or (not node[field].is_empty() and not ResourceLoader.exists(node[field], "Texture2D"))):
					context.problem(field, "图片资源不存在或类型错误")
			registry.commands[node.op].validate(context, node)
		errors.append_array(context.errors)
	bundle["sources"] = sources.duplicate()
	return _result(bundle)

func _validate_definitions(bundle: Dictionary, manifest: Dictionary) -> void:
	for id in bundle.flags:
		var definition: Variant = bundle.flags[id]
		var source = sources[manifest.flags]
		if not definition is Dictionary or not definition.has("default"):
			errors.append(source.diagnostic("/" + id, "Flag 缺少 default"))
			continue
		for bound in ["min", "max"]:
			if definition.has(bound) and not Rules.number(definition[bound]):
				errors.append(source.diagnostic("/" + id + "/" + bound, "范围必须是数值"))
		if definition.has("values") and not definition["values"] is Array:
			errors.append(source.diagnostic("/" + id + "/values", "values 必须为数组"))
		if not errors.is_empty(): continue
		var error: String = Rules.value_error(definition["default"], definition)
		if not error.is_empty(): errors.append(source.diagnostic("/" + id + "/default", error))
	if not bundle.catalog.get("items") is Dictionary or not bundle.catalog.get("entries") is Dictionary:
		errors.append(sources[manifest.catalog].diagnostic("", "catalog 需要 items 和 entries"))
		return
	for id in bundle.catalog.entries:
		var entry: Variant = bundle.catalog.entries[id]
		if not entry is Dictionary or not entry.get("name") is String:
			errors.append(sources[manifest.catalog].diagnostic("/entries/" + id, "图鉴缺少 name"))
	for id in bundle.catalog.items:
		var item: Variant = bundle.catalog.items[id]
		if not item is Dictionary or not item.get("name") is String:
			errors.append(sources[manifest.catalog].diagnostic("/items/" + id, "道具缺少 name"))
			continue
		if not Rules.integer(item.get("max_stack", 99)) or item.get("max_stack", 99) < 1:
			errors.append(sources[manifest.catalog].diagnostic("/items/" + id + "/max_stack", "堆叠上限必须为正整数"))
		for field in ["entry", "use_unlock"]:
			if item.has(field) and not bundle.catalog.entries.has(item[field]):
				errors.append(sources[manifest.catalog].diagnostic("/items/" + id + "/" + field, "未知图鉴"))
		var error: String = Rules.effects_error(item.get("effects", {}), bundle.flags, bundle.catalog)
		if not error.is_empty(): errors.append(sources[manifest.catalog].diagnostic("/items/" + id + "/effects", error))
	for id in bundle.characters:
		if not bundle.characters[id] is Dictionary or not bundle.characters[id].get("name") is String:
			errors.append(sources[manifest.characters].diagnostic("/" + id, "角色缺少 name"))
	if not bundle.locales.get("zh_CN") is Dictionary:
		errors.append(sources[manifest.locales].diagnostic("/zh_CN", "必须声明 zh_CN 默认语言"))
	for locale in bundle.locales:
		if not bundle.locales[locale] is Dictionary:
			errors.append(sources[manifest.locales].diagnostic("/" + locale, "语言表必须为对象"))
			continue
		for key in bundle.locales[locale]:
			if not bundle.locales[locale][key] is String:
				errors.append(sources[manifest.locales].diagnostic("/" + locale + "/" + key, "翻译必须为字符串"))
	var ending_ids: Dictionary = {}
	var priorities: Dictionary = {}
	var fallback := 0
	for index in bundle.endings.size():
		var ending: Variant = bundle.endings[index]
		var source = sources[manifest.endings]
		var pointer := "/" + str(index)
		if not ending is Dictionary or not ending.get("id") is String or not Rules.integer(ending.get("priority")):
			errors.append(source.diagnostic(pointer, "结局必须有 id 和整数 priority"))
			continue
		if ending_ids.has(ending.id) or priorities.has(ending.priority):
			errors.append(source.diagnostic(pointer, "结局 id 或优先级重复"))
		ending_ids[ending.id] = true
		priorities[ending.priority] = true
		var error: String = Rules.conditions_error(ending.get("conditions"), bundle.flags, bundle.catalog)
		if not error.is_empty(): errors.append(source.diagnostic(pointer + "/conditions", error))
		elif ending.conditions.is_empty(): fallback += 1
		if ending.has("entry") and not bundle.catalog.entries.has(ending.entry): errors.append(source.diagnostic(pointer + "/entry", "未知图鉴"))
		for field in ["title", "text"]:
			if not ending.get(field) is String: errors.append(source.diagnostic(pointer + "/" + field, "结局文本必须为字符串"))
	if fallback != 1: errors.append(sources[manifest.endings].diagnostic("", "必须有且仅有一个空条件兜底结局"))
	if not errors.is_empty(): return
	bundle.endings.sort_custom(func(a, b): return a.get("priority", 0) > b.get("priority", 0))
	if not bundle.endings.is_empty() and not bundle.endings.back().get("conditions", []).is_empty():
		errors.append(sources[manifest.endings].diagnostic("", "兜底结局必须为最低优先级"))

func _result(bundle: Dictionary) -> Dictionary:
	return {"bundle": bundle, "errors": errors.duplicate()}
