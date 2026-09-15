extends Control
## Procedural placeholder set, replaceable by illustrated background assets.
const BACKGROUND = preload("res://assets/backgrounds/black_page_room_v1.png")
var elapsed := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(720, 405)
	var background := TextureRect.new()
	background.texture = BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var shimmer := 0.08 + sin(elapsed * 1.7) * 0.025
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.13, 0.18, shimmer))
	for i in 46:
		var x := fmod(float(i) * 73.0 + elapsed * 52.0, w + 100.0) - 50.0
		var y := fmod(float(i) * 41.0 + elapsed * 180.0, h + 80.0) - 40.0
		draw_line(Vector2(x, y), Vector2(x - 6, y + 19), Color(0.55, 0.81, 0.9, 0.18), 1.0)
	var vignette := StyleBoxFlat.new()
	vignette.bg_color = Color(0.0, 0.02, 0.04, 0.13)
	draw_style_box(vignette, Rect2(Vector2.ZERO, size))
