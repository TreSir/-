extends Control
## 启动页：只负责把控制权交接出去，开始游戏之后才进剧情。
##
## 改造点：删掉原先用 _draw() 手绘的多边形笔记本与飘动圆点，换成实拍级背景图；
## 菜单从「描边方框按钮」改成左侧生长色条的行样式，层级更清楚。

signal start_requested
signal continue_requested
signal rain_muted_changed(value: bool)
signal music_muted_changed(value: bool)

const UI = preload("res://scripts/black_page/ui_style.gd")
const LAUNCH_BG = preload("res://assets/backgrounds/black_page_launch_v1.png")

var can_continue := false
var title: Label
var menu: VBoxContainer
var continue_button: Button
var settings_open := false
var rain_muted := false
var music_muted := false

var _hero: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()

func _build() -> void:
	var backdrop := TextureRect.new()
	backdrop.texture = LAUNCH_BG
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# 左侧压暗：菜单要压在暗部才读得清，右侧留亮给画面。
	var scrim := TextureRect.new()
	scrim.texture = _side_scrim()
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_hero = VBoxContainer.new()
	_hero.add_theme_constant_override("separation", 0)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)

	title = UI.heading("黑　页", UI.SIZE_DISPLAY)
	title.modulate.a = 0.0
	_hero.add_child(title)

	_hero.add_child(UI.spacer(18))
	var mark := HBoxContainer.new()
	mark.add_theme_constant_override("separation", 14)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick := ColorRect.new()
	tick.color = UI.HAIR_STRONG
	tick.custom_minimum_size = Vector2(40, 1)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(tick)
	var latin := UI.label("B L A C K   P A G E", UI.SIZE_MICRO + 1, UI.TEXT_MUTE)
	latin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.add_child(latin)
	_hero.add_child(mark)

	_hero.add_child(UI.spacer(38))
	menu = VBoxContainer.new()
	menu.add_theme_constant_override("separation", 2)
	menu.modulate.a = 0.0
	add_child(menu)
	_render_menu()

	var reveal := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reveal.tween_interval(0.9)
	reveal.tween_property(title, "modulate:a", 1.0, 1.0)
	reveal.tween_property(menu, "modulate:a", 1.0, 0.4)

func _side_scrim() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0118, 0.0275, 0.0392, 0.94))
	gradient.set_color(1, Color(0.0118, 0.0275, 0.0392, 0.16))
	gradient.add_point(0.44, Color(0.0118, 0.0275, 0.0392, 0.60))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.width = 256
	texture.height = 2
	return texture

func _layout() -> void:
	var s := size.y / 720.0
	var left := size.x * 0.087
	_hero.position = Vector2(left, size.y * 0.168)
	_hero.custom_minimum_size.x = size.x * 0.46
	_hero.size.x = size.x * 0.46
	title.add_theme_font_size_override("font_size", int(UI.SIZE_DISPLAY * s))
	menu.position = Vector2(left - 4, size.y * 0.430)
	menu.custom_minimum_size.x = size.x * 0.30

func _render_menu() -> void:
	for child in menu.get_children():
		menu.remove_child(child)
		child.queue_free()
	if settings_open:
		_add_row("设置", Callable(), "caption")
		_add_row("雨声：%s" % ("关" if rain_muted else "开"), _toggle_rain)
		_add_row("音乐：%s" % ("关" if music_muted else "开"), _toggle_music)
		_add_row("返回", func(): settings_open = false; _render_menu())
		return
	_add_row("开始游戏", func(): start_requested.emit())
	# 没有存档就不显示「继续游戏」——摆一个灰按钮没有意义。
	if can_continue:
		continue_button = _add_row("继续游戏", func(): continue_requested.emit())
	_add_row("设置", func(): settings_open = true; _render_menu())

func _add_row(text: String, callback: Callable, kind: String = "row") -> Button:
	var s := size.y / 720.0
	var button := Button.new()
	button.text = ""
	button.custom_minimum_size.y = 52 * s
	button.add_theme_font_size_override("font_size", int(17 * s))
	button.add_theme_stylebox_override("focus", UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))

	# 备注①：字贴着左侧色条，整体右移两个字宽（17px 字号 × 2 ≈ 34px）。
	# 注意：行内容是 FULL_RECT 锚点的 HBox，样式框的 content_margin 对它不生效，
	# 所以缩进必须写在 row.offset_left 上——原先的「悬停文字右移」因此从来没生效过。
	var pad := int(34 * s)
	var normal := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	normal.content_margin_left = pad
	normal.content_margin_right = 14

	if kind == "caption":
		button.disabled = true
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mute := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
		mute.content_margin_left = pad
		mute.content_margin_right = 14
		button.add_theme_stylebox_override("disabled", mute)
		button.add_theme_color_override("font_disabled_color", UI.TEXT_MUTE)
		button.text = text
		menu.add_child(button)
		return button

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", _row_hover_box(pad, 0.10))
	button.add_theme_stylebox_override("pressed", _row_hover_box(pad, 0.16))
	var dead := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	dead.content_margin_left = pad
	dead.content_margin_right = 14
	button.add_theme_stylebox_override("disabled", dead)
	button.add_theme_color_override("font_color", Color("c3d3db"))
	button.add_theme_color_override("font_hover_color", UI.TEXT_BRIGHT)
	button.add_theme_color_override("font_pressed_color", UI.ACCENT)
	button.add_theme_color_override("font_disabled_color", Color("4d5c66"))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = pad          # ← 真正把字往右推的是这一行
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	var name_label := UI.label(text, int(17 * s))
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color("c3d3db"))
	row.add_child(name_label)
	var rest := Control.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rest)
	button.add_child(row)

	if callback.is_valid():
		button.pressed.connect(callback)
	menu.add_child(button)
	return button

## 菜单行的高亮底。最左 0.4% 画一条接近实色的青线，充当原来的 2px 色条，
## 其余从给定浓度向右淡出到透明——右缘不再是一条硬切线。
## 用 StyleBoxTexture 包 GradientTexture2D，因为 StyleBoxFlat 画不了渐变填充。
func _row_hover_box(pad: int, alpha: float) -> StyleBoxTexture:
	var accent := Color(0.3843, 0.7608, 0.8667)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.004, 1.0])
	gradient.colors = PackedColorArray([
		Color(accent, 0.95), Color(accent, alpha), Color(accent, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.width = 512
	texture.height = 4
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.content_margin_left = pad
	box.content_margin_right = 14
	return box

func _toggle_rain() -> void:
	rain_muted = not rain_muted
	rain_muted_changed.emit(rain_muted)
	_render_menu()

func _toggle_music() -> void:
	music_muted = not music_muted
	music_muted_changed.emit(music_muted)
	_render_menu()

func close_to_game() -> void:
	set_process(false)
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	tween.tween_callback(queue_free)
