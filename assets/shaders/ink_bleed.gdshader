shader_type canvas_item;

// 墨迹渗出：文字像墨一样从纸纤维里一点点渗出来。
//
// 为什么用 shader 而不是淡入：策划案 §十一 写的是
// 「一点墨色从纸纤维里渗出来」「墨迹缓慢继续出现」——
// 整行淡入是「显示出来」，而墨是「沿着纤维蔓开」，两者的观感不一样。
//
// 做法：
//   1. 用节点局部坐标生成「纸纤维」噪声（横向拉长的低频 + 细颗粒两层）
//   2. progress 从 0 推到 1，把噪声阈值往上推 → 墨色沿纤维不规则蔓延
//   3. 阈值两侧留一个 bleed 宽的过渡带 → 边缘半透明，像洇开的墨
//
// 挂在一个 Label 上即可（Label 的 TEXTURE 是字形图集，UV 正确，字形不会变形）。

// 0 = 一个字都没渗出来，1 = 全部到位。
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// 纸纤维的密度。越大纤维越细。
uniform float fiber_scale : hint_range(1.0, 80.0) = 30.0;

// 洇开的宽度。越大边缘越模糊、越像湿墨。
uniform float bleed : hint_range(0.02, 0.45) = 0.15;

// 让噪声整体偏移，避免同一个页面的纸纹完全一样。
uniform float seed : hint_range(0.0, 100.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 用屏幕像素坐标当纸面（标签不动，所以等价于「贴在一张纸上」；
	// 比用 VERTEX 稳——Label 的字形是批量绘制的，VERTEX 未必是节点局部坐标）。
	vec2 p = FRAGCOORD.xy * 0.01 + vec2(seed);
	// 纸纤维：横向拉长的低频 + 各向同性的细颗粒。fbm 的取值落在 [0, ~0.95]。
	float fiber = fbm(vec2(p.x * fiber_scale * 0.32, p.y * fiber_scale)) * 0.72
			+ fbm(p * fiber_scale * 2.4) * 0.28;
	// ★ 阈值要在 fiber 的**实际取值范围**里扫：
	//   progress=0 → t=1.35（比所有 fiber 都高，一个字都不显）
	//   progress=1 → t=-0.15（比所有 fiber 都低，全部渗出）
	// 之前写成 progress*(1+2*bleed)-bleed，progress=1 时 t≈1.15 > 0.95，
	// 结果**一个字都不显示**——这个 bug 是截图才看出来的。
	float t = mix(1.35, -0.15, progress);
	float mask = smoothstep(t - bleed, t + bleed, fiber);
	// ★ 必须乘上进来的 COLOR（= 节点 modulate / 字体色），不能只用 tex.rgb：
	// 字形图集本身是白色的，Label 的颜色是靠 modulate 乘上去的。
	// 之前写成 COLOR = vec4(tex.rgb, ...) 直接把字体色冲掉了——黑字全变白字。
	COLOR = vec4(COLOR.rgb * tex.rgb, COLOR.a * tex.a * mask);
}
