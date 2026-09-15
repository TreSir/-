extends Button
## Compact icon-first navigation button. The text remains the accessible tooltip.
@export_enum("case", "people", "clue", "notebook", "save", "load", "restart", "reload") var glyph := "case"
var accent := Color("5fb9d2")
var hover_amount := 0.0

func _ready() -> void:
	flat = true
	custom_minimum_size = Vector2(60, 60)
	tooltip_text = text
	text = ""
	mouse_entered.connect(_animate.bind(1.0))
	mouse_exited.connect(_animate.bind(0.0))
	focus_entered.connect(_animate.bind(1.0))
	focus_exited.connect(_animate.bind(0.0))
	queue_redraw()

func _animate(target: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "hover_amount", target, 0.16)
	tween.tween_property(self, "scale", Vector2.ONE * (1.05 if target > 0.0 else 1.0), 0.16)
	tween.tween_callback(queue_redraw)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	var edge := accent.lerp(Color("405662"), 1.0 - hover_amount)
	draw_style_box(_box(Color("14212c").lerp(Color("1f3b49"), hover_amount), edge, 2), rect)
	var color := Color("aabfc8").lerp(accent, hover_amount)
	var c := size * 0.5
	match glyph:
		"case":
			draw_rect(Rect2(c + Vector2(-16, -11), Vector2(32, 23)), color, false, 2)
			draw_line(c + Vector2(-16, -4), c + Vector2(16, -4), color, 2)
			draw_line(c + Vector2(-9, 2), c + Vector2(10, 2), color, 2)
			draw_rect(Rect2(c + Vector2(-5, -15), Vector2(10, 5)), color, false, 2)
		"people":
			draw_circle(c + Vector2(0, -10), 7, color, false, 2)
			draw_arc(c + Vector2(0, 10), 13, PI * 1.1, PI * 1.9, 18, color, 2)
			draw_arc(c + Vector2(-12, 5), 7, PI * 1.2, PI * 1.9, 12, color.darkened(0.2), 2)
		"clue":
			draw_circle(c + Vector2(-4, -4), 11, color, false, 2)
			draw_line(c + Vector2(4, 4), c + Vector2(15, 15), color, 3)
			draw_line(c + Vector2(-9, -4), c + Vector2(1, -4), color, 2)
		"notebook":
			draw_rect(Rect2(c + Vector2(-14, -18), Vector2(28, 36)), color, false, 2)
			draw_line(c + Vector2(-8, -18), c + Vector2(-8, 18), color, 2)
			draw_line(c + Vector2(0, -8), c + Vector2(8, -8), color, 2)
			draw_line(c + Vector2(0, 0), c + Vector2(8, 0), color, 2)
		"save":
			draw_rect(Rect2(c + Vector2(-15, -15), Vector2(30, 30)), color, false, 2)
			draw_rect(Rect2(c + Vector2(-8, -14), Vector2(16, 10)), color, false, 2)
			draw_rect(Rect2(c + Vector2(-8, 4), Vector2(16, 9)), color, false, 2)
		"load":
			draw_arc(c, 15, -PI * 0.1, PI * 1.55, 20, color, 2)
			draw_line(c + Vector2(-15, -3), c + Vector2(-15, -14), color, 2)
			draw_line(c + Vector2(-15, -14), c + Vector2(-5, -14), color, 2)
			draw_line(c + Vector2(0, -7), c + Vector2(0, 7), color, 2)
			draw_line(c + Vector2(0, 7), c + Vector2(7, 1), color, 2)
		"restart":
			draw_arc(c, 15, -PI * 0.25, PI * 1.5, 20, color, 2)
			draw_line(c + Vector2(3, -15), c + Vector2(15, -15), color, 2)
			draw_line(c + Vector2(15, -15), c + Vector2(15, -3), color, 2)
		"reload":
			draw_arc(c, 15, PI * 0.1, PI * 0.9, 12, color, 2)
			draw_arc(c, 15, PI * 1.1, PI * 1.9, 12, color, 2)
			draw_line(c + Vector2(14, 4), c + Vector2(14, -7), color, 2)
			draw_line(c + Vector2(-14, -4), c + Vector2(-14, 7), color, 2)

func _box(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(10)
	return box
