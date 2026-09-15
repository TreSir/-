extends AudioStreamPlayer
## Quiet procedural rain: no external audio asset or licensing dependency.
var playback: AudioStreamGeneratorPlayback
var filtered := 0.0
var muted_by_player := false

func _ready() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.5
	self.stream = stream
	volume_db = -27.0
	play()
	playback = get_stream_playback()

func set_muted_by_player(value: bool) -> void:
	muted_by_player = value
	volume_db = -80.0 if value else -27.0

func _process(_delta: float) -> void:
	if playback == null: return
	for _frame in playback.get_frames_available():
		filtered = filtered * 0.985 + randf_range(-1.0, 1.0) * 0.015
		var drop: float = randf_range(-0.012, 0.012) if randf() > 0.992 else 0.0
		var sample: float = clampf(filtered + drop, -0.055, 0.055)
		playback.push_frame(Vector2(sample, sample))
