extends RefCounted
## 场景热区：背景图上的可点区域。
##
## 为什么是「程序化锚点」，而不是独立场景、也不是塞进 UI：
##   · scenes.gd 里「场景」的语义是『此刻你正在看着什么』，是整屏切换；
##     点背景上的一本书只是同一画面里的一个可点区域，不配占一个场景。
##   · 整套 UI 都是 Control 树 + 代码搭的；混进 Node2D/Area2D 只会引入
##     CanvasLayer 层级和输入顺序的新问题（容器默认 STOP 盖住兄弟那个坑），零收益。
##   · 所以用数据驱动的锚点：**锚点只负责触发，打开的内容该是什么还是什么**——
##     翻笔记本走 _open_notebook()，跟侧栏点进去是同一条路，不会长出第二套状态。
##
## 坐标必须是【归一化 UV】而不是屏幕像素：
##   _scene_layer 用 STRETCH_KEEP_ASPECT_COVERED，同一张图在不同窗口宽高比下
##   显示区域不同（铺满 + 裁切）。写死像素一缩放就飘；UV 跟着图片走，永远对得上。
## 取值方法：用 PIL 按比例裁出候选框人工核对（.workbuddy/scripts/hotspot_check.py）。

## scene_id -> [ {id, u, v, w, h, label, target} ]，u/v/w/h ∈ [0,1] 相对原图
const TABLE := {
	"room": [
		{"id": "notebook", "u": 0.470, "v": 0.548, "w": 0.115, "h": 0.082,
		 "label": "桌上的黑色笔记本", "target": "notebook"},
		{"id": "monitor", "u": 0.350, "v": 0.350, "w": 0.180, "h": 0.180,
		 "label": "亮着的显示器", "target": "monitor"},
		{"id": "phone", "u": 0.255, "v": 0.445, "w": 0.075, "h": 0.105,
		 "label": "床头柜上的手机", "target": "phone"},
		{"id": "board", "u": 0.855, "v": 0.065, "w": 0.140, "h": 0.410,
		 "label": "墙上的线索板", "target": "clues"},
	],
}


static func for_scene(id: String) -> Array:
	return TABLE.get(id, [])


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
