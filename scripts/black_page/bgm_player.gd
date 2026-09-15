extends AudioStreamPlayer
## 背景音乐播放器。
##
## 用两个 AudioStreamPlayer 做双缓冲：切曲时新曲淡入、旧曲淡出，
## 不会出现硬切或"两首同时响"的破绽。self 与 _aux 轮流当"当前轨"。
##
## 曲目素材放在 assets/audio/ 下，均为无缝循环、已做响度标准化，
## 所以这边只管播放与淡入淡出，不碰音量以外的任何处理。

const PLAY_DB := -17.0
const SILENT_DB := -80.0
const XFADE := 2.5

signal track_changed(path: String)

var muted_by_player := false
var current_path := ""

var _aux: AudioStreamPlayer
var _active: AudioStreamPlayer
var _idle: AudioStreamPlayer
var _fade: Tween


func _ready() -> void:
	_aux = AudioStreamPlayer.new()
	_aux.name = "BgmAux"
	_aux.volume_db = SILENT_DB
	add_child(_aux)
	volume_db = SILENT_DB
	_active = self
	_idle = _aux


## 切到指定曲目。同一首正在播则忽略，避免重复起播。
func play_track(path: String, fade: float = XFADE) -> void:
	if path.is_empty():
		return
	if path == current_path and _active.playing:
		return
	# 同雨声：素材缺失时安静跳过，不要每次启动刷警告。
	if not ResourceLoader.exists(path):
		return
	var track: AudioStream = load(path)
	if track == null:
		push_warning("背景音乐加载失败：%s" % path)
		return
	if track is AudioStreamOggVorbis:
		(track as AudioStreamOggVorbis).loop = true

	var incoming := _idle
	var outgoing := _active
	incoming.stream = track
	incoming.volume_db = SILENT_DB
	incoming.play()
	current_path = path

	_start_fade()
	_fade.tween_property(incoming, "volume_db", _level(), fade)
	_fade.tween_property(outgoing, "volume_db", SILENT_DB, fade)
	var stale := outgoing
	_fade.chain().tween_callback(func():
		stale.stop()
		stale.stream = null)

	_active = incoming
	_idle = outgoing
	track_changed.emit(path)


## 整块音乐淡出并停掉（进剧情、切场景时用）。
func fade_out(fade: float = 2.0) -> void:
	current_path = ""
	_start_fade()
	for player in [self, _aux]:
		_fade.tween_property(player, "volume_db", SILENT_DB, fade)
	_fade.chain().tween_callback(func():
		for player in [self, _aux]:
			player.stop()
			player.stream = null)


func set_muted_by_player(value: bool) -> void:
	muted_by_player = value
	if _fade != null and _fade.is_valid():
		_fade.kill()
	for player in [self, _aux]:
		if player.stream != null:
			player.volume_db = _level()


func _start_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel()
	_fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _level() -> float:
	return SILENT_DB if muted_by_player else PLAY_DB
