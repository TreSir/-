extends Node
## Interpreter dispatches command objects; no presentation dependencies.
signal view_changed(view: Dictionary, generation: int)
signal failed(message: String)
signal restart_requested
const Registry = preload("res://scripts/core/command_registry.gd")
const Compiler = preload("res://scripts/core/story_compiler.gd")
const Rules = preload("res://scripts/core/rules.gd")
var registry = Registry.new()
var bundle: Dictionary = {}
var cursor := ""
var waiting := false
var generation := 0
var debug_preview := false
var view: Dictionary = {}
var history: Array[String] = []
var manifest_path := ""
var auto_reload := true
var _elapsed := 0.0
var _fingerprint := ""
var _reload_paths: Array = []

func open(path: String) -> String:
	registry.discover()
	if not registry.errors.is_empty(): return "\n".join(registry.errors)
	var compiled: Dictionary = Compiler.new().compile(path, registry)
	if not compiled.errors.is_empty(): return "\n".join(compiled.errors)
	bundle = compiled.bundle
	manifest_path = path
	_reload_paths = bundle.sources.keys()
	_fingerprint = _signature()
	GameState.configure(bundle)
	Localization.configure(bundle.locales)
	return ""

func start() -> void:
	if bundle.is_empty():
		_fail("请先修复剧本加载错误")
		return
	debug_preview = false
	history.clear()
	GameState.reset()
	_enter(bundle.start)

func matches(conditions: Array) -> bool:
	return Rules.matches(conditions, GameState.flags, GameState.inventory)

func submit(input: Dictionary, ticket: int = -1) -> void:
	if ticket == -1: ticket = generation
	if not waiting or ticket != generation: return
	waiting = false
	generation += 1
	var node: Dictionary = bundle.nodes[cursor]
	var result: Dictionary = registry.commands[node.op].resume(self, node, input)
	_accept(result)

func _enter(id: String) -> void:
	waiting = false
	generation += 1
	for iteration in range(128):
		if not bundle.nodes.has(id):
			_fail("不存在的节点：" + id)
			return
		cursor = id
		history.append(id)
		if history.size() > 200: history.pop_front()
		EventBus.step_entered.emit(id)
		var node: Dictionary = bundle.nodes[id]
		var result: Dictionary = registry.commands[node.op].execute(self, node)
		if result.get("status") == "goto":
			id = str(result.get("target", ""))
			continue
		_accept(result)
		return
	_fail("自动跳转超过 128 次，请检查循环")

func _accept(result: Dictionary) -> void:
	match result.get("status"):
		"goto": _enter(str(result.get("target", "")))
		"wait":
			waiting = true
			view = result.get("view", {}).duplicate(true)
			view_changed.emit(view, generation)
		"hold": pass
		_: _fail(str(result.get("message", "命令返回值不合法")))

func refresh() -> void:
	if not waiting or not bundle.nodes.has(cursor): return
	var preview := debug_preview
	debug_preview = true
	var result: Dictionary = registry.commands[bundle.nodes[cursor].op].execute(self, bundle.nodes[cursor])
	debug_preview = preview
	generation += 1
	_accept(result)

func save_data() -> Dictionary:
	return {"story_id": bundle.id, "story_version": bundle.version, "cursor": cursor,
		"state": GameState.snapshot(), "locale": Localization.locale}

func restore(data: Dictionary) -> String:
	if data.get("story_id") != bundle.id or data.get("story_version") != bundle.version: return "存档剧情版本不匹配"
	var target: Variant = data.get("cursor")
	if not target is String or not bundle.nodes.has(target): return "存档节点已不存在"
	if not data.get("state") is Dictionary: return "存档缺少状态"
	var error: String = GameState.validate_snapshot(data.state)
	if not error.is_empty(): return error
	if not registry.commands[bundle.nodes[target].op].is_checkpoint(): return "存档不是可恢复的等待节点"
	GameState.restore(data.state)
	Localization.set_locale(str(data.get("locale", "zh_CN")))
	cursor = target
	waiting = true
	debug_preview = false
	refresh()
	return ""

func jump_to(id: String) -> String:
	if not OS.is_debug_build(): return "发行版禁用调试跳转"
	if not bundle.nodes.has(id): return "节点不存在"
	debug_preview = true
	_enter(id)
	return ""

func reload_story() -> String:
	var compiler = Compiler.new()
	var compiled: Dictionary = compiler.compile(manifest_path, registry)
	_reload_paths = compiler.sources.keys()
	if not compiled.errors.is_empty(): return "\n".join(compiled.errors)
	var candidate: Dictionary = compiled.bundle
	if candidate.id != bundle.id: return "热重载不能更换剧情 id"
	if not candidate.nodes.has(cursor): return "热重载被拒绝：当前节点已删除"
	if candidate.nodes[cursor].op != bundle.nodes[cursor].op: return "热重载被拒绝：当前节点命令类型改变"
	var state := GameState.snapshot()
	var error: String = GameState.validate_snapshot(state, candidate.flags, candidate.catalog)
	if not error.is_empty(): return "热重载被拒绝：" + error
	bundle = candidate
	GameState.configure(bundle)
	GameState.restore(state)
	Localization.configure(bundle.locales)
	Collections.catalog = bundle.catalog.duplicate(true)
	if waiting: refresh()
	EventBus.story_reloaded.emit()
	return ""

func _process(delta: float) -> void:
	if not auto_reload or bundle.is_empty() or not OS.is_debug_build(): return
	_elapsed += delta
	if _elapsed < 1.0: return
	_elapsed = 0.0
	if _signature() == _fingerprint: return
	var error := reload_story()
	_fingerprint = _signature()
	EventBus.notification.emit("剧情已热重载" if error.is_empty() else error)

func _signature() -> String:
	var result := ""
	for path in _reload_paths:
		result += str(path) + (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "<missing>")
	return result

func _fail(message: String) -> void:
	waiting = false
	generation += 1
	var location: Dictionary = bundle.nodes.get(cursor, {}).get("_source", {})
	failed.emit("%s:%d: %s" % [location.get("file", manifest_path), location.get("line", 1), message])
