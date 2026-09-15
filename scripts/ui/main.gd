extends Control
## Presentation adapter. Replace this scene/UI without changing story_runner.gd.

const SaveStore = preload("res://scripts/core/save_store.gd")
const Minigame = preload("res://scripts/core/minigame.gd")
@export_file("*.json") var story_path := "res://story/demo.json"

@onready var runner = $StoryRunner
@onready var speaker: Label = %Speaker
@onready var dialogue: RichTextLabel = %Dialogue
@onready var choices: VBoxContainer = %Choices
@onready var next_button: Button = %Next
@onready var status: Label = %Status
@onready var video: VideoStreamPlayer = %Video
@onready var host: Control = %MinigameHost

var store = SaveStore.new()
var active_game: Control
var unlocked: Array = []
var presentation_id := 0

func _ready() -> void:
	runner.step_presented.connect(_present)
	runner.flow_error.connect(_show_error)
	next_button.pressed.connect(_next)
	%Restart.pressed.connect(func(): runner.start())
	%Save.pressed.connect(_save)
	%Load.pressed.connect(_load)
	video.finished.connect(_video_finished)
	var error: String = runner.load_story(story_path)
	if not error.is_empty():
		_show_error(error)
		%Restart.disabled = true
		%Save.disabled = true
		%Load.disabled = true
		return
	var collection: Dictionary = store.read("endings")
	var saved_ids: Variant = collection.get("data", {}).get(runner.story["id"], [])
	if saved_ids is Array: unlocked = saved_ids
	runner.start()

func _present(step: Dictionary) -> void:
	presentation_id += 1
	_cleanup_activity()
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	%Background.texture = _texture(step.get("background", ""))
	%Portrait.texture = _texture(step.get("portrait", ""))
	speaker.text = str(step.get("speaker", ""))
	dialogue.text = str(step.get("text", ""))
	status.text = "已解锁结局：%d  ·  当前节点：%s" % [unlocked.size(), runner.current_id]
	next_button.visible = false
	%Save.disabled = false
	match step["type"]:
		"say":
			next_button.text = "继续"
			next_button.show()
		"choice":
			for index in range(step["options"].size()):
				var option: Dictionary = step["options"][index]
				if not runner.matches(option.get("conditions", [])): continue
				var button := Button.new()
				button.text = option["text"]
				button.custom_minimum_size.y = 44
				button.pressed.connect(runner.choose.bind(index))
				choices.add_child(button)
		"video":
			_start_video(step)
		"minigame":
			_start_minigame(step)
		"ending":
			speaker.text = str(step.get("title", "故事结束"))
			_unlock(step["ending_id"])
			next_button.text = "重新开始"
			next_button.show()

func _next() -> void:
	match runner.current_step().get("type"):
		"say": runner.advance()
		"ending": runner.start()
		"video":
			if runner.current_step().get("skippable", true):
				runner.complete_activity({"played": false, "skipped": true})

func _start_video(step: Dictionary) -> void:
	var path: String = step.get("path", "")
	if path.is_empty():
		_finish_activity.call_deferred(presentation_id, {"played": false, "skipped": true})
		return
	var stream: Resource = load(path) if ResourceLoader.exists(path) else null
	if not stream is VideoStream:
		_activity_error("无法加载视频：" + path)
		return
	video.stream = stream
	video.show()
	video.play()
	next_button.text = "跳过视频"
	next_button.visible = step.get("skippable", true)

func _video_finished() -> void:
	if runner.current_step().get("type") == "video":
		runner.complete_activity({"played": true, "skipped": false})

func _start_minigame(step: Dictionary) -> void:
	var path: String = step["scene"]
	var packed: Resource = load(path) if ResourceLoader.exists(path) else null
	if not packed is PackedScene:
		_activity_error("无法加载小游戏：" + path)
		return
	var instance := (packed as PackedScene).instantiate()
	if not instance is Minigame:
		instance.free()
		_activity_error("小游戏根节点必须继承 scripts/core/minigame.gd")
		return
	active_game = instance
	host.show()
	host.add_child(active_game)
	_connect_game(instance)
	instance.begin(step.get("config", {}).duplicate(true), runner.variables.duplicate(true))

func _connect_game(instance: Minigame) -> void:
	var ticket := presentation_id
	instance.completed.connect(func(result: Dictionary): _finish_activity.call_deferred(ticket, result), CONNECT_ONE_SHOT)

func _finish_activity(ticket: int, result: Dictionary) -> void:
	if ticket == presentation_id: runner.complete_activity(result)

func _activity_error(message: String) -> void:
	status.text = message
	var button := Button.new()
	button.text = "继续剧情（本次活动记为失败）"
	button.pressed.connect(func(): runner.complete_activity({"success": false, "played": false, "error": message}))
	choices.add_child(button)

func _cleanup_activity() -> void:
	video.stop()
	video.stream = null
	video.hide()
	if is_instance_valid(active_game):
		host.remove_child(active_game)
		active_game.queue_free()
	active_game = null
	host.hide()

func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path): return null
	return load(path) as Texture2D

func _save() -> void:
	if not runner.waiting: return
	var error: String = store.write("slot_1", runner.snapshot())
	status.text = "进度已保存。视频和小游戏读档时会从头开始。" if error.is_empty() else error

func _load() -> void:
	var saved: Dictionary = store.read("slot_1")
	if saved.has("error"):
		status.text = saved["error"]
		return
	var error: String = runner.restore(saved["data"])
	if not error.is_empty(): status.text = error

func _unlock(id: String) -> void:
	if not unlocked.has(id): unlocked.append(id)
	var collection: Dictionary = store.read("endings").get("data", {})
	collection[runner.story["id"]] = unlocked
	var error: String = store.write("endings", collection)
	status.text = "已解锁结局：%d  ·  可重新开始探索其他分支" % unlocked.size() if error.is_empty() else error

func _show_error(message: String) -> void:
	presentation_id += 1
	_cleanup_activity()
	next_button.hide()
	%Save.disabled = true
	status.text = message
	push_error(message)
