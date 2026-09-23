shader_type canvas_item;

// One RGBA portrait supplies all identity states without shifting the character.
uniform int identity_state = 0; // 0: clear, 1: uncertain, 2: locked

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (identity_state == 2) {
		COLOR = vec4(vec3(0.025, 0.08, 0.11), source.a);
	} else if (identity_state == 1) {
		vec4 total = vec4(0.0);
		float weight_sum = 0.0;
		for (int y = -2; y <= 2; y++) {
			for (int x = -2; x <= 2; x++) {
				float weight = 1.0 / (1.0 + float(x * x + y * y));
				vec4 sample_color = texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * 5.0);
				total.rgb += sample_color.rgb * sample_color.a * weight;
				total.a += sample_color.a * weight;
				weight_sum += weight;
			}
		}
		float alpha = total.a / weight_sum;
		vec3 color = total.rgb / max(total.a, 0.0001);
		COLOR = vec4(color * 0.55, alpha);
	} else {
		COLOR = source;
	}
}
