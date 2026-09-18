extends Control
## UV 热区层：把背景图上的「UV 比例矩形」变成可点区域。
##
## 为什么有这个文件：序章（rect 来自 prologue.json）和房间（来自 hotspots.gd 表）
## 曾经各写一套建层 + 定位，**连 UV→屏幕的换算都各写了一份**。
## 现在合成一套——换算就放在本文件 `rect_for()`，它考虑了封面式拉伸的留边。
##
## 用法：
##
##     var layer := HotspotLayer.new()
##     add_child(layer)
##     layer.setup(items, tex_size, func(item): ...)   # 建层
##     layer.relayout()                                 # 尺寸变了就重排
##
## `items` 每项是一个字典，至少含 UV 比例，其余字段原样带回给回调：
##
##     键名 `uv` 或 `rect`（序章的 JSON 用的是 rect）——
##     数组写法 [x, y, w, h]   —— 序章 JSON 用这个
##     字典写法 {u, v, w, h}   —— hotspots.gd 的表用这个
##
## `decorate` 可选：拿到 (box, item) 让你加自己的装饰。
## 房间那套要悬停辉光与调试标签，序章不需要——所以它必须可选，不能塞进公共路径。

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
	# UV 有三种写法，按优先级找：
	#   item.uv / item.rect  —— 序章 JSON 是这个
	#   item 自己就带 u/v/w/h —— hotspots.gd 的表是这个
	var source: Variant = item.get("uv", item.get("rect", null))
	if source == null: source = item
	box.set_meta("uv", uv_dict(source))
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

## UV 的三种写法都收，出来的永远是 `rect_for` 认的 {u,v,w,h}：
##
##     数组 [x, y, w, h]      —— 序章 JSON 的 rect
##     字典 {u, v, w, h}      —— hotspots.gd 的表
##     字典 {x, y, w, h}      —— 以防以后有人写成 x/y
static func uv_dict(uv: Variant) -> Dictionary:
	if uv is Array and (uv as Array).size() >= 4:
		var a: Array = uv
		return {"u": float(a[0]), "v": float(a[1]), "w": float(a[2]), "h": float(a[3])}
	if uv is Dictionary:
		var d: Dictionary = uv
		for keys in [["u", "v", "w", "h"], ["x", "y", "w", "h"]]:
			if d.has(keys[0]) and d.has(keys[1]) and d.has(keys[2]) and d.has(keys[3]):
				return {
					"u": float(d[keys[0]]), "v": float(d[keys[1]]),
					"w": float(d[keys[2]]), "h": float(d[keys[3]]),
				}
	return {}

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
