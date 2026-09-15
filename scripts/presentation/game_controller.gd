extends Node
## Composition root: translates service state into read-only view models.
const Console = preload("res://scripts/presentation/debug_console.gd")
@export var persist_progress := true
var runtime
var screen
var console
var library_kind := ""
func _ready() -> void:
	_boot.call_deferred()
func _boot() -> void:
	screen = get_parent()
	runtime = screen.get_node("StoryRunner")
	runtime.view_changed.connect(_present)
	runtime.failed.connect(screen.show_error)
	runtime.restart_requested.connect(func(): runtime.start.call_deferred())
	screen.next_requested.connect(_next)
	screen.choice_requested.connect(func(index: int, generation: int): runtime.submit({"choice": index}, generation))
	screen.activity_completed.connect(func(result: Dictionary, generation: int): runtime.submit({"result": result}, generation))
	screen.restart_requested.connect(runtime.start)
	screen.save_requested.connect(_save)
	screen.load_requested.connect(_load)
	screen.library_requested.connect(_library)
	screen.use_requested.connect(_use)
	screen.language_requested.connect(_language)
	screen.debug_requested.connect(func():
		if console != null: console.toggle())
	EventBus.notification.connect(screen.show_status)
	var error: String = runtime.open("res://data/game.json")
	if not error.is_empty():
		screen.show_error(error)
		return
	Collections.configure(runtime.bundle, persist_progress)
	_labels()
	if OS.is_debug_build():
		console = Console.new()
		console.runtime = runtime
		screen.add_child(console)
	EventBus.locale_changed.connect(_labels)
	EventBus.story_reloaded.connect(_labels)
	runtime.start()

func _present(data: Dictionary, generation: int) -> void:
	var model := data.duplicate(true)
	for key in ["text", "title"]:
		if model.has(key): model[key] = Localization.text(str(model[key]))
	model["speaker_name"] = Localization.text(runtime.bundle.characters.get(model.get("speaker", ""), {}).get("name", ""))
	model["continue_label"] = Localization.text("@continue")
	model["restart_label"] = Localization.text("@restart")
	model["skip_label"] = Localization.text("@skip")
	model["context"] = GameState.flags.duplicate(true)
	for option in model.get("options", []): option.text = Localization.text(option.text)
	screen.render(model, generation)
	screen.show_status("图鉴收集：%d / %d" % [Collections.discovered.size(), Collections.catalog.entries.size()])

func _next(generation: int) -> void:
	if runtime.view.get("op") == "video":
		if runtime.view.get("skippable", true): runtime.submit({"result": {"played": false, "skipped": true}}, generation)
	else: runtime.submit({}, generation)

func _save() -> void:
	if not runtime.waiting: return
	if runtime.debug_preview:
		screen.show_status("调试预览不写入正式存档。重新开始可恢复正常游玩。")
		return
	var error: String = SaveService.save_slot("slot_1", runtime.save_data())
	screen.show_status("进度已保存" if error.is_empty() else error)
func _load() -> void:
	if runtime.bundle.is_empty(): return
	var result: Dictionary = SaveService.load_slot("slot_1", runtime.bundle)
	var error: String = result.get("error", "")
	if error.is_empty(): error = runtime.restore(result.data)
	screen.show_status("进度已恢复" if error.is_empty() else error)

func _library(kind: String) -> void:
	if Collections.catalog.is_empty(): return
	library_kind = kind
	var rows: Array = []
	var catalog: Dictionary = Collections.catalog
	if kind == "bag":
		for id in GameState.inventory:
			var item: Dictionary = catalog.items[id]
			rows.append({"id": id, "name": "%s × %d · %s" % [Localization.text(item.name), GameState.inventory[id], item.get("category", "道具")],
				"description": Localization.text(item.get("description", "")), "usable": item.get("usable", false)})
	else:
		for id in catalog.entries:
			var entry: Dictionary = catalog.entries[id]
			var known := Collections.discovered.has(id)
			rows.append({"id": id, "name": "[%s] %s" % [entry.get("category", "图鉴"), Localization.text(entry.name) if known or not entry.get("secret", false) else "???"],
				"description": Localization.text(entry.get("description", "")) if known else "尚未解锁"})
	screen.library.display(Localization.text("@bag" if kind == "bag" else "@codex"), rows)

func _use(id: String) -> void:
	if runtime.debug_preview:
		screen.show_status("调试预览不使用道具")
		return
	var error: String = Collections.use_item(id)
	if error.is_empty():
		# Refresh only choices: never restart a live video/minigame after drinking tea.
		if runtime.view.get("op") == "choice": runtime.refresh()
		_library(library_kind)
	else: screen.library.heading.text = error

func _language() -> void:
	Localization.set_locale("en" if Localization.locale == "zh_CN" else "zh_CN")
	if runtime.view.get("op") in ["say", "choice", "ending"]: runtime.refresh()
func _labels() -> void:
	var labels: Dictionary = {}
	for key in ["save", "load", "restart", "bag", "codex"]: labels[key] = Localization.text("@" + key)
	screen.set_labels(labels)
