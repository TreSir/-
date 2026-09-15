extends AudioStreamPlayer
## 雨声环境音。
##
## 原先这里是运行时用 AudioStreamGenerator 现场合成的白噪音：22050Hz、单极低通、
## 幅度压在 ±0.055，出来的就是一层发闷的嘶声，所以听着难受。
## 现在改成播放外部录制素材（见 audio_tracks.gd / assets/audio/），
## 素材本身已经做好无缝循环（交叉淡化接缝）与 EBU R128 响度标准化，
## 引擎这边只负责淡入淡出，不再做任何合成。
##
## 对外接口保持不变（volume_db / set_muted_by_player），main.gd 无需改动。

const AudioTracks = preload("res://scripts/black_page/audio_tracks.gd")

const TRACK := AudioTracks.RAIN_DEFAULT
const PLAY_DB := -13.0
const SILENT_DB := -80.0
const FADE_IN := 2.5

var muted_by_player := false

var _fade: Tween


func _ready() -> void:
	var track := _load_track(TRACK)
	if track == null:
		return
	stream = track
	volume_db = SILENT_DB
	# 一直保持播放：静音只是把音量压到 -80dB，这样取消静音是瞬间且无缝的，
	# 反复开关也不会产生重新起播的爆音。
	play()
	_fade_to(PLAY_DB, FADE_IN)


## OGG 的循环标志在导入设置里可能没打开，这里兜底强制打开。
## 没有它，雨声放完一遍就会静音。
func _load_track(path: String) -> AudioStream:
	# 音轨是外部素材，仓库里可能没有。先查存在性，缺了就安静地不播，
	# 别在每次启动都刷一堆 load 失败的红字——那是素材缺失，不是 bug。
	if not ResourceLoader.exists(path):
		return null
	var loaded: AudioStream = load(path)
	if loaded == null:
		push_warning("雨声音轨加载失败：%s" % path)
		return null
	if loaded is AudioStreamOggVorbis:
		(loaded as AudioStreamOggVorbis).loop = true
	return loaded


func set_muted_by_player(value: bool) -> void:
	muted_by_player = value
	if not playing:
		play()
	_fade_to(SILENT_DB if value else PLAY_DB, 0.6)


func _fade_to(target_db: float, duration: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade.tween_property(self, "volume_db", target_db, duration)
