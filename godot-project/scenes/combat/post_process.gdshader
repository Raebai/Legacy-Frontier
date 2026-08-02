shader_type canvas_item;
render_mode blend_mix;
// Reactive screen-space grade for the combat arenas ("the look"). Reads the
// framebuffer (everything drawn below this CanvasLayer) and outputs a graded,
// gameplay-reactive image. Base grade is tasteful; the punch comes from the
// live uniforms PostProcess.gd feeds each frame — aberration follows the camera
// trauma, a shockwave ring fires on epic moments, heat-haze pulses on fire.
// Complements (does not replace) the WorldEnvironment HDR bloom.

// ⚠ `filter_linear`, NOT `filter_linear_mipmap`, AND THAT IS A PERFORMANCE FIX,
// NOT A DOWNGRADE. `filter_linear_mipmap` makes the renderer build a full mipmap
// CHAIN of the framebuffer every single frame. Every fetch below uses screen-space
// UVs at 1:1, so the implicit derivatives are ~1 texel and every one of them lands
// on LOD 0 — the pyramid was built and never read. Measured on the shipping arena
// at 1920x1080 (tools/profile_post_variants.gd): 10% of the whole frame, for an
// image that is bit-identical. If a future effect wants a blurred read of the
// screen it must ask for the LOD explicitly (`textureLod`), and putting the mipmap
// hint back is then a deliberate, priced decision rather than a default nobody
// chose.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// --- Reactive (driven live by PostProcess.gd) ---
uniform float trauma : hint_range(0.0, 1.0) = 0.0;   // camera trauma -> aberration + micro-warp
uniform float heat : hint_range(0.0, 1.0) = 0.0;     // fire beats -> heat-haze
uniform vec3 shock = vec3(0.5, 0.5, 0.0);            // xy = ripple center (screen uv), z = age (s)
uniform float shock_amp = 0.0;                        // ripple strength (decays to 0)

// --- Chromatic aberration ---
uniform float aberration_base = 0.7;     // px at idle (lens whisper)
uniform float aberration_trauma = 4.5;   // extra px at full trauma

// --- Color grade ---
uniform float grade_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 lift = vec3(0.0, 0.0, 0.01);
uniform vec3 gain = vec3(1.05, 1.03, 1.10);
uniform float grade_gamma = 1.02;
uniform float saturation = 1.16;
uniform vec3 shadow_tint = vec3(0.02, 0.02, 0.09);    // cool shadows
uniform vec3 highlight_tint = vec3(0.10, 0.06, 0.00);  // warm highlights
uniform float split_strength = 0.14;

// --- Vignette ---
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.34;
uniform float vignette_softness = 0.62;   // 0..1, lower = tighter dark ring
uniform vec3 vignette_tint = vec3(0.015, 0.015, 0.04);

// --- Grain ---
uniform float grain = 0.025;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_center = uv - vec2(0.5);

	// Shockwave: an expanding ring that pushes UVs radially outward as it passes,
	// then fades. shock.z = age -> ring radius; shock_amp = overall strength.
	if (shock_amp > 0.0001) {
		vec2 d = uv - shock.xy;
		float dist = length(d);
		float radius = shock.z * 0.9;               // ring travels outward with age
		float band = smoothstep(0.28, 0.0, abs(dist - radius));
		float wave = sin((dist - radius) * 46.0);
		uv += normalize(d + vec2(1e-5)) * wave * band * shock_amp;
	}

	// Heat-haze: gentle animated warp (fire beats push `heat`).
	if (heat > 0.001) {
		uv += vec2(
			sin(uv.y * 42.0 + TIME * 3.2),
			cos(uv.x * 38.0 + TIME * 2.6)
		) * heat * 0.0045;
	}

	// A whisper of trauma-driven warp so a hit feels felt even before aberration.
	uv += from_center * trauma * 0.004 * sin(TIME * 40.0);

	// Chromatic aberration: radial R/B split, scaling from center + with trauma.
	float ab_px = aberration_base + aberration_trauma * trauma;
	vec2 ab = from_center * ab_px * SCREEN_PIXEL_SIZE * 2.0;
	vec3 col;
	col.r = texture(screen_tex, uv + ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - ab).b;

	// Color grade: lift/gain/gamma -> saturation -> split-tone.
	vec3 graded = col * gain + lift;
	graded = pow(max(graded, vec3(0.0)), vec3(1.0 / grade_gamma));
	float luma = dot(graded, vec3(0.299, 0.587, 0.114));
	graded = mix(vec3(luma), graded, saturation);
	graded += mix(shadow_tint, highlight_tint, clamp(luma, 0.0, 1.0)) * split_strength;
	col = mix(col, graded, grade_strength);

	// Vignette: darken toward the tint at the edges, clear center.
	float vig = smoothstep(1.0, vignette_softness, length(from_center) * 1.41421356);
	col = mix(mix(col, vignette_tint, vignette_strength), col, vig);

	// Subtle animated grain for texture.
	if (grain > 0.001) {
		float n = hash(SCREEN_UV * vec2(1920.0, 1080.0) + fract(TIME) * 137.0) - 0.5;
		col += n * grain;
	}

	COLOR = vec4(col, 1.0);
}
