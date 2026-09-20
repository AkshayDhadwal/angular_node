class_name GameEnvironment
extends Node

## Lighting, sky and post-processing. Most of the perceived quality of the
## scene comes from here rather than from the geometry.

static func build(parent: Node3D) -> void:
	_build_sun(parent)
	_build_environment(parent)


static func _build_sun(parent: Node3D) -> void:
	# Low, warm key light — late afternoon reads far better than overhead noon.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, 132.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	parent.add_child(sun)

	# Cool fill from the opposite side so shadows aren't dead black.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -48.0, 0.0)
	fill.light_color = Color(0.78, 0.85, 0.98)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	parent.add_child(fill)


static func _build_environment(parent: Node3D) -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.24, 0.42, 0.72)
	sky_material.sky_horizon_color = Color(0.78, 0.8, 0.79)
	sky_material.sky_curve = 0.14
	sky_material.ground_bottom_color = Color(0.2, 0.22, 0.21)
	sky_material.ground_horizon_color = Color(0.68, 0.7, 0.68)
	sky_material.sun_angle_max = 14.0
	sky_material.sun_curve = 0.1

	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.25
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0

	# Contact shadows in corners and under eaves — cheap, and a big readability win.
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.6
	env.ssao_power = 1.8
	env.ssao_detail = 0.6

	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Aerial perspective: distant geometry fades toward the sky, which is what
	# makes a map feel large rather than like a diorama.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.7, 0.76, 0.82)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.5

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.06
	env.adjustment_brightness = 1.0

	world_env.environment = env
	parent.add_child(world_env)
