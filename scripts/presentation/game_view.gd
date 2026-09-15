extends Control
## Renders presentation data and emits user intent. No story, save or flag logic.
signal next_requested(ticket: int)
signal choice_requested(index: int, ticket: int)
signal activity_completed(result: Dictionary, ticket: int)
signal save_requested
signal load_requested
signal restart_requested
signal library_requested(kind: String)
signal use_requested(id: String)
signal language_requested
signal debug_requested
const Minigame = preload("res://scripts/core/minigame.gd")
const Library = preload("res://scripts/presentation/library_panel.gd")
@onready var video: VideoStreamPlayer = %Video
@onready var host: Control = %MinigameHost
var active_game: Control
var ticket := 0
var model: Dictionary = {}
var library
var bag_button: Button
var codex_button: Button
var debug_button: Button

func _ready() -> void:
	%Next.pressed.connect(func(): next_requested.emit(ticket))
	%Save.pressed.connect(func(): save_requested.emit())
	%Load.pressed.connect(func(): load_requested.emit())
	%Restart.pressed.connect(func(): restart_requested.emit())
	video.finished.connect(func(): activity_completed.emit({"played": true, "skipped": false}, ticket))
	bag_button = _toolbar_button("背包", func(): library_requested.emit("bag"))
	codex_button = _toolbar_button("图鉴", func(): library_requested.emit("codex"))
	_toolbar_button("中/EN", func(): language_requested.emit())
	debug_button = _toolbar_button("调试 F1", func(): debug_requested.emit())
	debug_button.visible = OS.is_debug_build()
	library = Library.new()
	add_child(library)
	library.use_requested.connect(func(id: String): use_requested.emit(id))
	$Margin/Rows/Toolbar/Title.text = "剧情框架 · 示例"

func _toolbar_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	$Margin/Rows/Toolbar.add_child(button)
	return button

func set_labels(labels: Dictionary) -> void:
	%Save.text = labels.save
	%Load.text = labels.load
	%Restart.text = labels.restart
	bag_button.text = labels.bag
	codex_button.text = labels.codex

func render(data: Dictionary, generation: int) -> void:
	ticket = generation
	model = data
	_cleanup_activity()
	_clear_choices()
	%Background.texture = _texture(data.get("background", ""))
	%Portrait.texture = _texture(data.get("portrait", ""))
	%Speaker.text = str(data.get("speaker_name", ""))
	%Dialogue.text = str(data.get("text", ""))
	%Next.hide()
	%Save.disabled = false
	match data.get("op"):
		"say":
			%Next.text = data.get("continue_label", "继续")
			%Next.show()
		"choice":
			for option in data.get("options", []):
				var button := Button.new()
				button.text = option.text
				button.custom_minimum_size.y = 42
				button.pressed.connect(func(): choice_requested.emit(option.index, generation))
				%Choices.add_child(button)
		"video":
			_start_video(data, generation)
		"minigame":
			_start_game(data, generation)
		"ending":
			%Speaker.text = str(data.get("title", ""))
			%Next.text = data.get("restart_label", "重新开始")
			%Next.show()
		_:
			show_error("没有注册该演出视图：" + str(data.get("op")))

func _start_video(data: Dictionary, generation: int) -> void:
	if data.get("path", "").is_empty():
		_emit_activity.call_deferred({"played": false, "skipped": true}, generation)
		return
	var stream = load(data.path)
	if not stream is VideoStream:
		_activity_error("无法加载视频", generation)
		return
	video.stream = stream
	video.show()
	video.play()
	%Next.text = data.get("skip_label", "跳过视频")
	%Next.visible = data.get("skippable", true)

func _start_game(data: Dictionary, generation: int) -> void:
	var packed = load(data.scene)
	if not packed is PackedScene:
		_activity_error("无法加载小游戏场景", generation)
		return
	var instance = packed.instantiate()
	if not instance is Minigame:
		instance.free()
		_activity_error("小游戏根节点必须继承 minigame.gd", generation)
		return
	active_game = instance
	host.show()
	host.add_child(instance)
	instance.completed.connect(func(result: Dictionary): _emit_activity.call_deferred(result, generation), CONNECT_ONE_SHOT)
	instance.begin(data.get("config", {}).duplicate(true), data.get("context", {}).duplicate(true))

func _emit_activity(result: Dictionary, generation: int) -> void:
	if generation == ticket: activity_completed.emit(result, generation)

func _activity_error(message: String, generation: int) -> void:
	show_status(message)
	var button := Button.new()
	button.text = "结束本次活动并继续"
	button.pressed.connect(func(): _emit_activity({"success": false, "score": 0, "played": false, "skipped": true}, generation))
	%Choices.add_child(button)

func _cleanup_activity() -> void:
	video.stop()
	video.stream = null
	video.hide()
	if is_instance_valid(active_game):
		host.remove_child(active_game)
		active_game.queue_free()
	active_game = null
	host.hide()

func _clear_choices() -> void:
	for child in %Choices.get_children():
		%Choices.remove_child(child)
		child.queue_free()

func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D if not path.is_empty() else null

func show_status(message: String) -> void:
	%Status.text = message

func show_error(message: String) -> void:
	ticket += 1
	_cleanup_activity()
	_clear_choices()
	%Next.hide()
	%Save.disabled = true
	show_status(message)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		debug_requested.emit()
		get_viewport().set_input_as_handled()
