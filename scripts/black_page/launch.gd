extends Control
## The actual first screen. It only hands off control; story starts after Start Game.
signal start_requested
signal continue_requested
signal rain_muted_changed(value: bool)
var can_continue := false
var title: Label
var menu: VBoxContainer
var continue_button: Button
var settings_open := false
var rain_muted := false
var elapsed := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()
	queue_redraw()

func _build() -> void:
	title = Label.new()
	title.text = "黑 页"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color("d6e6e9"))
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.modulate.a = 0.0
	add_child(title)
	menu = VBoxContainer.new()
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu.add_theme_constant_override("separation", 12)
	menu.modulate.a = 0.0
	add_child(menu)
	_render_menu()
	var reveal := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reveal.tween_interval(1.1)
	reveal.tween_property(title, "modulate:a", 1.0, 1.25)
	reveal.tween_property(menu, "modulate:a", 1.0, 0.45)

func _layout() -> void:
	title.position = Vector2(size.x * 0.25, size.y * 0.17)
	title.size = Vector2(size.x * 0.50, 92)
	menu.position = Vector2(size.x * 0.16, size.y * 0.40)
	menu.size = Vector2(260, 205)

func _render_menu() -> void:
	for child in menu.get_children(): child.queue_free()
	if settings_open:
		_add_button("设置", Callable(), true)
		_add_button("雨声：%s" % ("关" if rain_muted else "开"), _toggle_rain)
		_add_button("返回", func(): settings_open = false; _render_menu())
		return
	_add_button("开始游戏", func(): start_requested.emit())
	continue_button = _add_button("继续游戏", func(): continue_requested.emit(), false, not can_continue)
	_add_button("设置", func(): settings_open = true; _render_menu())

func _add_button(text: String, callback: Callable, title_button: bool = false, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.disabled = disabled
	button.flat = title_button
	if title_button:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", Color("75919a"))
	else:
		button.add_theme_font_size_override("font_size", 20)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.02, 0.05, 0.07, 0.0)
		normal.border_color = Color(0.55, 0.72, 0.76, 0.30)
		normal.border_width_left = 2
		normal.set_content_margin_all(10)
		var hover := normal.duplicate()
		hover.bg_color = Color(0.18, 0.34, 0.39, 0.28)
		hover.border_color = Color(0.72, 0.91, 0.94, 0.92)
		var disabled_style := StyleBoxFlat.new()
		disabled_style.bg_color = Color(0.02, 0.05, 0.07, 0.0)
		disabled_style.border_color = Color(0.28, 0.36, 0.39, 0.18)
		disabled_style.border_width_left = 2
		disabled_style.set_content_margin_all(10)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.add_theme_stylebox_override("disabled", disabled_style)
		button.add_theme_color_override("font_disabled_color", Color("65747a"))
	if callback.is_valid():
		button.pressed.connect(callback)
	menu.add_child(button)
	return button

func _toggle_rain() -> void:
	rain_muted = not rain_muted
	rain_muted_changed.emit(rain_muted)
	_render_menu()

func close_to_game() -> void:
	set_process(false)
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	tween.tween_callback(queue_free)

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("030508"))
	# Closed notebook: a hand-drawn perspective block on the right.
	var center := Vector2(size.x * 0.70, size.y * 0.55)
	var breathe := 0.30 + sin(elapsed * 0.75) * 0.05
	var front := PackedVector2Array([center + Vector2(-92, -50), center + Vector2(80, -50), center + Vector2(76, 72), center + Vector2(-95, 65)])
	var top := PackedVector2Array([front[0], front[1], center + Vector2(113, -78), center + Vector2(-58, -80)])
	var side := PackedVector2Array([front[1], center + Vector2(113, -78), center + Vector2(109, 42), front[2]])
	draw_colored_polygon(front, Color(0.025, 0.04, 0.05, 1.0))
	draw_colored_polygon(top, Color(0.05, 0.075, 0.08, 1.0))
	draw_colored_polygon(side, Color(0.018, 0.028, 0.035, 1.0))
	draw_polyline(front, Color(0.72, 0.88, 0.9, breathe), 2.0, true)
	draw_polyline(top, Color(0.72, 0.88, 0.9, breathe * 0.8), 2.0, true)
	draw_polyline(side, Color(0.72, 0.88, 0.9, breathe * 0.65), 2.0, true)
	draw_arc(center + Vector2(-10, 10), 29, -2.6, 0.4, 16, Color(0.72, 0.88, 0.9, breathe * 0.55), 2.0)
	var ink: float = clampf((elapsed - 1.05) / 1.25, 0.0, 1.0)
	if ink > 0.0:
		for index in 30:
			var x := size.x * 0.5 - 96.0 + fmod(float(index) * 37.0, 192.0)
			var y := size.y * 0.27 + fmod(float(index) * 19.0, 34.0)
			draw_circle(Vector2(x, y), 0.8 + fmod(float(index), 3.0), Color(0.58, 0.74, 0.77, ink * 0.17))
