extends Node
## 音效播放器：一次性的短音。
##
## 和 BGM / 雨声的区别：那两个是**常驻**的（一直循环，走淡入淡出），
## 这里是**事件型**的（嗡一声、砰一下），所以单独一个组件，互不干扰。
##
## 用一个小池子轮流播：同一个音效连着响两次时，第二次不会把第一次掐断。
##
## 用法：
##
##     sfx.play(AudioTracks.SFX_PHONE_BUZZ)
##     sfx.play(path, -3.0)                 # 需要更响就传 db
##
## 素材缺失时**安静跳过**——不刷警告，也不阻断剧情（和 BGM / 雨声一个规矩）。

## 池子大小。同时最多叠这么多个音效，够用了。
const POOL := 6
## 默认音量。音效本来就短，比 BGM 响一档才听得见。
const DEFAULT_DB := -7.0

var muted_by_player := false

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
## 缓存已加载的流，避免每次响都去 load()。
var _cache: Dictionary = {}

func _ready() -> void:
	for index in POOL:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % index
		add_child(player)
		_pool.append(player)

## 放一个一次性音效。`db` 越低越轻。
func play(path: String, db: float = DEFAULT_DB) -> void:
	if muted_by_player or path.is_empty(): return
	var stream := _stream_of(path)
	if stream == null: return
	var player := _pool[_next]
	_next = (_next + 1) % POOL
	player.stream = stream
	player.volume_db = db
	player.play()

## 玩家在设置里关掉音效（和音乐、雨声各自的开关独立）。
func set_muted_by_player(value: bool) -> void:
	muted_by_player = value
	if not value: return
	for player in _pool:
		player.stop()

func _stream_of(path: String) -> AudioStream:
	if _cache.has(path): return _cache[path]
	if not ResourceLoader.exists(path):
		# 素材缺失：安静跳过。剧情不该因为缺一个音效就卡住。
		_cache[path] = null
		return null
	var stream: AudioStream = load(path)
	_cache[path] = stream
	return stream
