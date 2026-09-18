extends Control
## UV 热区层：把背景图上的「UV 比例矩形」变成可点区域。
##
## 为什么有这个文件：建层 + 定位和 UV→屏幕的换算曾经散在场景各处各写一份。
## 现在合成一套——换算就放在本文件 `rect_for()`，它考虑了封面式拉伸的留边。
##
## 用法：
##
##     var layer := HotspotLayer.new()
##     add_child(layer)
##     layer.setup(items, tex_size, func(item): ...)   # 建层
##     layer.relayout()                                 # 尺寸变了就重排
##
## `items` 每项是一个字典，带 u/v/w/h（相对原图的比例，见 hotspots.gd 的表），
## 其余字段原样带回给回调。
##
## `decorate` 可选：拿到 (box, item) 让你加自己的装饰。房间那套要悬停辉光与
## 调试标签——所以它必须可选，不能塞进公共路径。

var _items: Array = []
var _tex_size := Vector2.ZERO
var _on_press: Callable
var _decorate: Callable

## 建好整层。重复调用会先清空。
func setup(items: Array, tex_size: Vector2, on_press: Callable,
		decorate: Callable = Callable()) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_items = items
	_tex_size = tex_size
	_on_press = on_press
	_decorate = decorate
	clear()
	for item in _items:
		if not (item is Dictionary): continue
		add_child(_make(item))
	relayout()

func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

## 热区是 UV 比例，窗口尺寸一变就得重算。
func relayout() -> void:
	var view := size
	if view.x <= 0.0 or view.y <= 0.0 or _tex_size.x <= 0.0 or _tex_size.y <= 0.0:
		return
	for child in get_children():
		var box := child as Control
		var uv: Variant = box.get_meta("uv", null)
		if uv == null: continue
		var rect := rect_for(uv_dict(uv), view, _tex_size)
		box.position = rect.position
		box.size = rect.size

func _make(item: Dictionary) -> Control:
	var box := Control.new()
	box.name = str(item.get("id", item.get("label", "Hotspot")))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.set_meta("uv", uv_dict(item))
	# 无底色、无描边——热区平时必须完全隐形，只有悬停才有一点反馈。
	var blank := StyleBoxEmpty.new()
	box.add_theme_stylebox_override("panel", blank)
	box.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			if _on_press.is_valid(): _on_press.call(item))
	if _decorate.is_valid():
		_decorate.call(box, item)
	return box

## 取一条热区记录里的 UV，出来的是 `rect_for` 认的 {u, v, w, h}。
## 键名就是 u/v/w/h（hotspots.gd 的表就是这个形状）；缺一个就返回空，不猜。
static func uv_dict(item: Dictionary) -> Dictionary:
	for key in ["u", "v", "w", "h"]:
		if not item.has(key): return {}
	return {
		"u": float(item.u), "v": float(item.v),
		"w": float(item.w), "h": float(item.h),
	}

## 把一个热区的 UV 换算成屏幕矩形。
## TextureRect(EXPAND_IGNORE_SIZE + STRETCH_KEEP_ASPECT_COVERED) 的铺图算法就是
## 取较大的缩放比铺满、再居中，这里照抄，保证和画面严格对齐：
##   scale = max(view / tex)，origin = (view - tex * scale) / 2
static func rect_for(uv: Dictionary, view: Vector2, tex_size: Vector2) -> Rect2:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0 or view.x <= 0.0 or view.y <= 0.0:
		return Rect2()
	var scale: float = maxf(view.x / tex_size.x, view.y / tex_size.y)
	var origin: Vector2 = (view - tex_size * scale) * 0.5
	return Rect2(
		origin + Vector2(float(uv["u"]), float(uv["v"])) * tex_size * scale,
		Vector2(float(uv["w"]), float(uv["h"])) * tex_size * scale)
