extends RefCounted
## 《黑页》共用视觉令牌与控件工厂。
##
## 改造前每个界面各自拼 StyleBox，字号清一色 18，导致所有元素长得一样、没有层级。
## 这里把所有颜色、字号、圆角、内边距集中成一处，三个界面（启动页 / 序章 / 房间）共用。
##
## 尺寸是逻辑像素：基准视口 1280×720（project.godot 的 viewport / 窗口都是它，
## 16:9 统一时这些数值没有重调——比例一致，绝对值会被整体等比缩放）。

# ── 颜色 ────────────────────────────────────────────────────────────────
const INK := Color(0.0196, 0.0314, 0.0431, 1.0)
const VEIL := Color(0.0118, 0.0275, 0.0431, 0.52)
const PANEL_BG := Color(0.0314, 0.0588, 0.0824, 0.90)
const PANEL_SOFT := Color(0.0706, 0.1176, 0.1490, 0.66)

const HAIR := Color(0.4941, 0.6980, 0.7686, 0.16)
const HAIR_STRONG := Color(0.4941, 0.6980, 0.7686, 0.34)

const TEXT := Color("cfdce3")
const TEXT_BRIGHT := Color("e8f2f6")
const TEXT_DIM := Color("7d909c")
const TEXT_MUTE := Color("566872")

const ACCENT := Color("62c2dd")
const ACCENT_SOFT := Color(0.3843, 0.7608, 0.8667, 0.14)
const ACCENT_EDGE := Color(0.3843, 0.7608, 0.8667, 0.42)

const AMBER := Color("e0a45e")
const AMBER_EDGE := Color(0.8784, 0.6431, 0.3686, 0.40)

const ACT_BG := Color(0.0784, 0.1412, 0.1804, 0.62)
const ACT_BG_HOVER := Color(0.1176, 0.2196, 0.2745, 0.80)

## 界面改成「只剩文字漂在画面上」之后，可读性全靠描边。深色描边压暗底、
## 亮底上自动形成暗晕，不必再给每块内容垫一层底色。
const OUTLINE := Color(0.0118, 0.0275, 0.0392, 0.88)
const OUTLINE_SIZE := 5

# ── 字号（四档，别再全用同一个号）──────────────────────────────────────
const SIZE_DISPLAY := 68
const SIZE_TITLE := 24
const SIZE_BODY := 18
const SIZE_UI := 15
const SIZE_SMALL := 13
const SIZE_MICRO := 11

# ── 布局（逻辑像素，1280×720 基准）──────────────────────────────────────
const TOPBAR_H := 58
const RAIL_W := 84
const MARGIN_L := 111
const MARGIN_R := 111
const ACT_H := 53
const BTN_H := 46
## 底部对话框的固定高度（逻辑像素）。
##
## 为什么是固定值：对话框**不能**被内容往任何方向挤。
## 早先按内容测高，结果是长文本往上顶、短文本缩回去，翻页时上下乱跳，
## 而且量出来的高度还依赖换行缓存，不稳定。固定住最省事，排版也最工整。
## 288 是按序章最长那一页（约 5 行正文 + 标题行 + 脚注）留的余量。
const DIALOG_H := 280

## 打字机速度（字/秒）。**要调快慢就改这一个数字**，主界面和序章共用。
## 数字 = 每秒出几个字，越大越快。中文阅读舒适区大概在 30~50。
const TYPE_SPEED := 48.0

## 场景切换转场的时长（秒）：先压黑 TRANSITION_OUT，换完图再亮回来 TRANSITION_IN。
const TRANSITION_OUT := 0.26
const TRANSITION_IN := 0.42

# ── 字体 ────────────────────────────────────────────────────────────────
static func sans() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"])
	return font

static func serif() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Source Han Serif SC", "Noto Serif SC", "Songti SC", "SimSun", "serif"])
	font.font_italic = false
	return font

# ── StyleBox 工厂 ───────────────────────────────────────────────────────
static func box(bg: Color, border: Color, radius: int = 12, pad: int = 0, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	if pad > 0:
		style.set_content_margin_all(pad)
	return style

static func panel(pad: int = 26, radius: int = 16) -> StyleBoxFlat:
	return box(PANEL_BG, HAIR, radius, pad)

static func card(pad: int = 16) -> StyleBoxFlat:
	return box(PANEL_SOFT, HAIR, 12, pad)

# ── 全局 Theme ──────────────────────────────────────────────────────────
static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = sans()
	theme.default_font_size = SIZE_UI
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_color("font_outline_color", "Label", OUTLINE)
	theme.set_constant("outline_size", "Label", OUTLINE_SIZE)
	theme.set_color("font_outline_color", "Button", OUTLINE)
	theme.set_constant("outline_size", "Button", OUTLINE_SIZE)

	theme.set_stylebox("normal", "Button", box(Color(0.0784, 0.1412, 0.1804, 0.55), HAIR, 10, 14))
	theme.set_stylebox("hover", "Button", box(ACT_BG_HOVER, HAIR_STRONG, 10, 14))
	theme.set_stylebox("pressed", "Button", box(Color(0.0392, 0.0863, 0.1098, 0.75), ACCENT_EDGE, 10, 14))
	theme.set_stylebox("disabled", "Button", box(Color(0.0392, 0.0627, 0.0784, 0.40), Color(0.4941, 0.6980, 0.7686, 0.08), 10, 14))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT_EDGE, 10, 14))
	theme.set_color("font_hover_color", "Button", TEXT_BRIGHT)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", TEXT_MUTE)

	theme.set_stylebox("panel", "PanelContainer", panel())

	var scroll := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", scroll)

	# 滚动条：只给颜色不给内容边距的话最小宽度是 0，等于看不见——玩家不会知道这页能翻。
	var track := box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 3, 0, 0)
	track.content_margin_left = 2
	track.content_margin_right = 2
	theme.set_stylebox("scroll", "VScrollBar", track)
	var grabber := box(Color(0.4941, 0.6980, 0.7686, 0.55), Color(0, 0, 0, 0), 4, 0, 0)
	grabber.content_margin_left = 4
	grabber.content_margin_right = 4
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	var grabber_hot := box(ACCENT, Color(0, 0, 0, 0), 4, 0, 0)
	grabber_hot.content_margin_left = 4
	grabber_hot.content_margin_right = 4
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_hot)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_hot)
	return theme

# ── 控件工厂 ────────────────────────────────────────────────────────────
## 短标签默认【不】自动换行。
##
## 踩过的坑：开了自动换行的 Label，最小宽度是「最长单词」——中文就是**一个字**。
## 放进 HBoxContainer 里它只会拿到 1 个字的宽度，于是整句话被压成竖排。
## 需要换行的长文本一律用 flow()，它会显式占满可用宽度。
static func label(text: String, size: int = SIZE_UI, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node

## 长正文专用：自动换行 + 占满可用宽度。
static func flow(text: String, size: int = SIZE_UI, color: Color = TEXT) -> Label:
	var node := label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

## ── 底部对话框 ─────────────────────────────────────────────────────────
##
## 一块「塞剧情」的框：**高度固定，底边钉死在屏幕底部**。
## 内容贴底排列，所以正文的底边永远不动，长文本只在框内向上展开，
## 框本身既不会被往上顶、也不会被往下拖。
##
## 不要往里面加「剧情记录」之类的标签——它就是个对话框。
static func dialogue_box() -> PanelContainer:
	var box := PanelContainer.new()
	var empty := StyleBoxEmpty.new()
	box.add_theme_stylebox_override("panel", empty)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_bottom = 0
	box.offset_top = -DIALOG_H
	return box

## 对话框的渐隐遮罩：从透明向下渐深，保证文字压在亮画面上也读得出。
static func dialogue_scrim() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0118, 0.0275, 0.0392, 0.0))
	gradient.set_color(1, Color(0.0118, 0.0275, 0.0392, 0.92))
	gradient.add_point(0.46, Color(0.0118, 0.0275, 0.0392, 0.42))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 2
	texture.height = 256
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

## 把对话框对回固定位置：底边贴屏幕，高度恒为 height。
## 换文案之后调用一次即可（内容贴底，所以不需要重新量高度）。
static func layout_dialogue(box: Control, height: float = DIALOG_H) -> void:
	if box == null or not box.is_inside_tree():
		return
	box.offset_bottom = 0
	box.offset_top = -height

## 给内容右边留一段空白：内容 + 一个按 tail 比例伸缩的占位，排成一行。
## 这样正文只占 (1 / (1 + tail)) 的宽度，避免整屏宽的长行。
static func narrow(node: Control, tail: float = 0.62) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_stretch_ratio = 1.0
	row.add_child(node)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.size_flags_stretch_ratio = tail
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	return row

static func heading(text: String, size: int = SIZE_TITLE) -> Label:
	var node := label(text, size, TEXT_BRIGHT)
	node.add_theme_font_override("font", serif())
	return node

static func rule(alpha: float = 1.0) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(HAIR.r, HAIR.g, HAIR.b, HAIR.a * alpha)
	line.custom_minimum_size.y = 1
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

static func spacer(height: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size.y = height
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func stretch() -> Control:
	var node := Control.new()
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func chip(text: String, color: Color = TEXT_DIM, soft: Color = Color(0, 0, 0, 0), edge: Color = HAIR_STRONG) -> Label:
	var node := label(text, SIZE_MICRO, color)
	var style := box(soft, edge, 999, 0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	node.add_theme_stylebox_override("normal", style)
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return node

static func accent_chip(text: String) -> Label:
	return chip(text, ACCENT, ACCENT_SOFT, ACCENT_EDGE)

static func primary_button(text: String, size: int = SIZE_UI) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = BTN_H
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_stylebox_override("normal", box(ACCENT, ACCENT, 10, 14))
	button.add_theme_stylebox_override("hover", box(Color("7bd0e8"), Color("7bd0e8"), 10, 14))
	button.add_theme_stylebox_override("pressed", box(Color("4aa9c4"), Color("4aa9c4"), 10, 14))
	button.add_theme_stylebox_override("disabled", box(Color(0.3843, 0.7608, 0.8667, 0.22), Color(0, 0, 0, 0), 10, 14))
	button.add_theme_color_override("font_disabled_color", TEXT_MUTE)
	return button

static func ghost_button(text: String, size: int = SIZE_UI) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = BTN_H
	button.add_theme_font_size_override("font_size", size)
	# 幽灵按钮必须是「细边框 + 透明底」，否则压在亮画面上会变成一块灰饼。
	button.add_theme_stylebox_override("normal", box(Color(0.0118, 0.0275, 0.0392, 0.22), HAIR, 10, 14))
	button.add_theme_stylebox_override("hover", box(Color(0.3843, 0.7608, 0.8667, 0.12), ACCENT_EDGE, 10, 14))
	button.add_theme_stylebox_override("pressed", box(Color(0.3843, 0.7608, 0.8667, 0.18), ACCENT, 10, 14))
	button.add_theme_stylebox_override("disabled", box(Color(0, 0, 0, 0), Color(0.4941, 0.6980, 0.7686, 0.10), 10, 14))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", ACCENT)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	return button

## 行动项：**无底色**的列表行，只有一条底线 + 箭头 + 右侧消耗角标。
##
## 去掉底色是这次改版的核心诉求——主界面要「只剩文字漂在画面上」。
## 可点性改由底线、箭头和悬停高亮来承担，不再靠一块深色矩形。
static func action_row(title: String, cost: String, enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = ""
	button.custom_minimum_size.y = ACT_H
	button.disabled = not enabled
	button.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	button.add_theme_stylebox_override("hover", box(Color(0.3843, 0.7608, 0.8667, 0.11), Color(0, 0, 0, 0), 0, 0, 0))
	button.add_theme_stylebox_override("pressed", box(Color(0.3843, 0.7608, 0.8667, 0.20), Color(0, 0, 0, 0), 0, 0, 0))
	button.add_theme_stylebox_override("disabled", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))

	var underline := ColorRect.new()
	underline.color = HAIR
	underline.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	underline.offset_top = -1
	underline.offset_bottom = 0
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(underline)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := label(title, SIZE_UI, TEXT if enabled else TEXT_MUTE)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var chevron := label("›", SIZE_UI, AMBER if enabled else TEXT_MUTE)
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chevron)
	var cost_label := label(cost, SIZE_MICRO, AMBER if enabled else TEXT_MUTE)
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cost_label)
	button.add_child(row)
	return button

## 弹出菜单里的一行。
static func menu_row(text: String, hint: String = "") -> Button:
	var button := Button.new()
	button.text = ""
	button.custom_minimum_size.y = 46
	button.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	button.add_theme_stylebox_override("hover", box(ACCENT_SOFT, Color(0, 0, 0, 0), 0, 0, 0))
	button.add_theme_stylebox_override("pressed", box(Color(0.3843, 0.7608, 0.8667, 0.20), Color(0, 0, 0, 0), 0, 0, 0))
	button.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -14
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := label(text, SIZE_SMALL, TEXT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if not hint.is_empty():
		var hint_label := label(hint, SIZE_MICRO, TEXT_MUTE)
		hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(hint_label)
	button.add_child(row)
	return button

## 左侧栏项目：图标 + 文字标签，当前项带左侧竖条。
static func nav_item(text: String) -> Button:
	var button := Button.new()
	button.text = ""
	button.flat = true
	button.custom_minimum_size = Vector2(RAIL_W, 78)
	button.tooltip_text = text
	button.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	button.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.045), Color(0, 0, 0, 0), 0, 0, 0))
	button.add_theme_stylebox_override("pressed", box(ACCENT_SOFT, Color(0, 0, 0, 0), 0, 0, 0))
	button.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))

	var mark := ColorRect.new()
	mark.color = ACCENT
	mark.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	mark.offset_left = 0
	mark.offset_right = 3
	mark.offset_top = 20
	mark.offset_bottom = -20
	mark.visible = false
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(mark)

	var box_node := VBoxContainer.new()
	box_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box_node.alignment = BoxContainer.ALIGNMENT_CENTER
	box_node.add_theme_constant_override("separation", 7)
	box_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := _NavGlyph.new()
	icon.glyph = text
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.base = TEXT_DIM
	box_node.add_child(icon)
	var caption := label(text, SIZE_MICRO, TEXT_MUTE)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box_node.add_child(caption)
	button.add_child(box_node)
	button.set_meta("caption", caption)
	button.set_meta("glyph", icon)
	button.set_meta("mark", mark)
	return button

static func icon_button(text: String, glyph: String = "") -> Button:
	var button := Button.new()
	button.text = ""
	button.tooltip_text = text
	button.custom_minimum_size = Vector2(42, 42)
	button.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 10, 0, 0))
	button.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.05), HAIR, 10, 0))
	button.add_theme_stylebox_override("pressed", box(ACCENT_SOFT, ACCENT_EDGE, 10, 0))
	button.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	var node := _NavGlyph.new()
	node.glyph = glyph if not glyph.is_empty() else text
	node.base = TEXT_MUTE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.custom_minimum_size = Vector2(20, 20)
	button.add_child(node)
	return button


## 图标绘制：用文字当键，画一组简单的线框图标，避免依赖图片资源。
class _NavGlyph extends Control:
	const GLYPH_IDLE := Color("7d909c")
	const GLYPH_ACTIVE := Color("62c2dd")
	const GLYPH_HOVER := Color("cfe3ea")

	var glyph := "案件"
	var base := GLYPH_IDLE
	var hovered := false

	func set_active(active: bool) -> void:
		base = GLYPH_ACTIVE if active else GLYPH_IDLE
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var parent := get_parent()
		while parent != null:
			if parent is Button:
				parent.mouse_entered.connect(func(): hovered = true; queue_redraw())
				parent.mouse_exited.connect(func(): hovered = false; queue_redraw())
				break
			parent = parent.get_parent()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var unit: float = minf(size.x, size.y) / 24.0
		var ink := base.lerp(GLYPH_HOVER, 0.85) if hovered else base
		var w: float = maxf(1.4, 1.6 * unit)
		match glyph:
			"案件":
				draw_rect(Rect2(c + Vector2(-9, -10) * unit, Vector2(18, 20) * unit), ink, false, w)
				draw_line(c + Vector2(-5, -10) * unit, c + Vector2(-5, 10) * unit, ink, w)
				draw_line(c + Vector2(-1, -3) * unit, c + Vector2(6, -3) * unit, ink, w)
				draw_line(c + Vector2(-1, 3) * unit, c + Vector2(6, 3) * unit, ink, w)
			"人物":
				draw_circle(c + Vector2(0, -4) * unit, 4.2 * unit, ink, false, w)
				draw_arc(c + Vector2(0, 10) * unit, 7.4 * unit, PI, TAU, 20, ink, w)
			"线索":
				draw_circle(c + Vector2(-1.6, -1.6) * unit, 6.4 * unit, ink, false, w)
				draw_line(c + Vector2(3.2, 3.2) * unit, c + Vector2(9.5, 9.5) * unit, ink, w)
			"黑页":
				draw_rect(Rect2(c + Vector2(-9, -8.5) * unit, Vector2(18, 17) * unit), ink, false, w)
				draw_line(c + Vector2(-3, -8.5) * unit, c + Vector2(-3, 8.5) * unit, ink, w)
			"保存":
				draw_rect(Rect2(c + Vector2(-8, -8) * unit, Vector2(16, 16) * unit), ink, false, w)
				draw_rect(Rect2(c + Vector2(-4, -7) * unit, Vector2(8, 5.5) * unit), ink, false, w)
				draw_rect(Rect2(c + Vector2(-4, 2.5) * unit, Vector2(8, 5) * unit), ink, false, w)
			"读取":
				draw_rect(Rect2(c + Vector2(-9, -6) * unit, Vector2(18, 12.5) * unit), ink, false, w)
				draw_arc(c + Vector2(0, -6) * unit, 4.5 * unit, PI, TAU, 14, ink, w)
			"重新开始":
				draw_arc(c, 7.4 * unit, -PI * 0.35, PI * 1.25, 24, ink, w)
				draw_polyline(PackedVector2Array([
					c + Vector2(5.5, -7.5) * unit,
					c + Vector2(9.6, -1.6) * unit,
					c + Vector2(3.2, -0.6) * unit,
				]), ink, w, true)
			"重载":
				draw_line(c + Vector2(-4.5, -8) * unit, c + Vector2(-4.5, 4.6) * unit, ink, w)
				draw_polyline(PackedVector2Array([
					c + Vector2(-8.2, 1.4) * unit,
					c + Vector2(-4.5, 6) * unit,
					c + Vector2(-0.8, 1.4) * unit,
				]), ink, w, true)
				draw_line(c + Vector2(4.5, 8) * unit, c + Vector2(4.5, -4.6) * unit, ink, w)
				draw_polyline(PackedVector2Array([
					c + Vector2(0.8, -1.4) * unit,
					c + Vector2(4.5, -6) * unit,
					c + Vector2(8.2, -1.4) * unit,
				]), ink, w, true)
			"菜单":
				draw_line(c + Vector2(-9, -6) * unit, c + Vector2(9, -6) * unit, ink, w)
				draw_line(c + Vector2(-9, 0) * unit, c + Vector2(9, 0) * unit, ink, w)
				draw_line(c + Vector2(-9, 6) * unit, c + Vector2(9, 6) * unit, ink, w)
			"关闭":
				draw_line(c + Vector2(-6, -6) * unit, c + Vector2(6, 6) * unit, ink, w)
				draw_line(c + Vector2(6, -6) * unit, c + Vector2(-6, 6) * unit, ink, w)
			_:
				draw_circle(c, 6 * unit, ink, false, w)
