class_name Props
extends Node

## Reusable construction helpers: buildings with pitched roofs and windows,
## plus the street clutter that makes a town read as a place rather than a
## set of boxes.

static func material(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	return mat


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D, solid := true, rot_y := 0.0) -> MeshInstance3D:
	if solid and parent is StaticBody3D:
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.position = pos
		shape.rotation.y = rot_y
		parent.add_child(shape)

	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	node.rotation.y = rot_y
	node.material_override = mat
	parent.add_child(node)
	return node


# ------------------------------------------------------------------ buildings

static func building(parent: Node3D, center: Vector3, size: Vector3, yaw: float, wall_color: Color, roof_color: Color, storeys := 1) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = yaw
	parent.add_child(body)

	var w := size.x
	var d := size.z
	var storey_h := size.y
	var h := storey_h * float(storeys)
	var t := 0.3

	var wall_mat := material(wall_color, 0.95)
	var trim_mat := material(wall_color.darkened(0.3), 0.85)
	var roof_mat := material(roof_color, 0.85)
	var floor_mat := material(Color(0.36, 0.32, 0.29), 0.95)
	var glass_mat := material(Color(0.14, 0.19, 0.24), 0.15, 0.4)
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(0.1, 0.12, 0.14)

	# Plinth and floor
	box(body, Vector3(w + 0.5, 0.35, d + 0.5), Vector3(0.0, 0.17, 0.0), trim_mat)
	box(body, Vector3(w, 0.2, d), Vector3(0.0, 0.42, 0.0), floor_mat)

	var base_y := 0.35
	var door_w := 1.9
	var door_h := 2.5
	var front_z := -d * 0.5 + t * 0.5

	# Walls
	box(body, Vector3(w, h, t), Vector3(0.0, base_y + h * 0.5, d * 0.5 - t * 0.5), wall_mat)
	box(body, Vector3(t, h, d), Vector3(-w * 0.5 + t * 0.5, base_y + h * 0.5, 0.0), wall_mat)
	box(body, Vector3(t, h, d), Vector3(w * 0.5 - t * 0.5, base_y + h * 0.5, 0.0), wall_mat)

	# Front wall split around a doorway
	var side := (w - door_w) * 0.5
	box(body, Vector3(side, h, t), Vector3(-(door_w * 0.5 + side * 0.5), base_y + h * 0.5, front_z), wall_mat)
	box(body, Vector3(side, h, t), Vector3(door_w * 0.5 + side * 0.5, base_y + h * 0.5, front_z), wall_mat)
	box(body, Vector3(door_w, h - door_h, t), Vector3(0.0, base_y + door_h + (h - door_h) * 0.5, front_z), wall_mat)

	# Door frame
	box(body, Vector3(door_w + 0.3, 0.18, 0.12), Vector3(0.0, base_y + door_h + 0.09, front_z - t * 0.5), trim_mat, false)
	box(body, Vector3(0.16, door_h, 0.12), Vector3(-door_w * 0.5, base_y + door_h * 0.5, front_z - t * 0.5), trim_mat, false)
	box(body, Vector3(0.16, door_h, 0.12), Vector3(door_w * 0.5, base_y + door_h * 0.5, front_z - t * 0.5), trim_mat, false)

	# Windows, per storey, recessed into the side and front walls
	for level in storeys:
		var y := base_y + storey_h * float(level) + storey_h * 0.55
		_window(body, Vector3(-(door_w * 0.5 + side * 0.5), y, front_z - t * 0.55), 0.0, glass_mat, trim_mat)
		_window(body, Vector3(door_w * 0.5 + side * 0.5, y, front_z - t * 0.55), 0.0, glass_mat, trim_mat)
		_window(body, Vector3(-w * 0.5 + t * 0.45, y, -d * 0.2), PI * 0.5, glass_mat, trim_mat)
		_window(body, Vector3(-w * 0.5 + t * 0.45, y, d * 0.2), PI * 0.5, glass_mat, trim_mat)
		_window(body, Vector3(w * 0.5 - t * 0.45, y, -d * 0.2), PI * 0.5, glass_mat, trim_mat)
		_window(body, Vector3(w * 0.5 - t * 0.45, y, d * 0.2), PI * 0.5, glass_mat, trim_mat)

	# Eaves and pitched roof
	var eave_y := base_y + h
	box(body, Vector3(w + 0.8, 0.22, d + 0.8), Vector3(0.0, eave_y + 0.11, 0.0), trim_mat)
	_pitched_roof(body, Vector3(0.0, eave_y + 0.22, 0.0), w + 0.8, d + 0.8, roof_mat)

	# Chimney
	box(body, Vector3(0.7, 1.5, 0.7), Vector3(w * 0.28, eave_y + 1.1, d * 0.22), trim_mat, false)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, base_y + h - 0.7, 0.0)
	lamp.omni_range = maxf(w, d) * 1.4
	lamp.light_energy = 0.85
	lamp.light_color = Color(1.0, 0.88, 0.7)
	lamp.shadow_enabled = false
	body.add_child(lamp)


static func _window(parent: Node3D, pos: Vector3, rot_y: float, glass: StandardMaterial3D, trim: StandardMaterial3D) -> void:
	box(parent, Vector3(1.3, 1.1, 0.08), pos, glass, false, rot_y)
	box(parent, Vector3(1.5, 0.14, 0.12), pos + Vector3(0.0, 0.62, 0.0), trim, false, rot_y)
	box(parent, Vector3(1.5, 0.14, 0.12), pos + Vector3(0.0, -0.62, 0.0), trim, false, rot_y)
	box(parent, Vector3(0.1, 1.1, 0.1), pos, trim, false, rot_y)


static func _pitched_roof(parent: Node3D, base: Vector3, w: float, d: float, mat: StandardMaterial3D) -> void:
	# Two slabs leaning against each other, plus gable ends to close the sides.
	var rise := d * 0.32
	var slope_len := sqrt(pow(d * 0.5, 2.0) + pow(rise, 2.0))
	var angle := atan2(rise, d * 0.5)

	for sign_z in [-1.0, 1.0]:
		var slab := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(w, 0.22, slope_len)
		slab.mesh = mesh
		slab.material_override = mat
		slab.position = base + Vector3(0.0, rise * 0.5, sign_z * d * 0.25)
		# Positive sign_z must tilt the far edge DOWN, so the sign follows
		# sign_z directly — negating it flips both slabs into a valley.
		slab.rotation.x = angle * sign_z
		parent.add_child(slab)

	var gable := material(mat.albedo_color.lightened(0.1), 0.95)
	for sign_x in [-1.0, 1.0]:
		var tri := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(d, rise, 0.25)
		tri.mesh = prism
		tri.material_override = gable
		tri.position = base + Vector3(sign_x * (w * 0.5 - 0.12), rise * 0.5, 0.0)
		tri.rotation.y = PI * 0.5
		parent.add_child(tri)


# --------------------------------------------------------------- street props

static func crate(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	parent.add_child(body)
	var wood := material(Color(0.46, 0.33, 0.19), 0.95)
	var slat := material(Color(0.38, 0.27, 0.15), 0.95)
	box(body, Vector3(1.1, 1.1, 1.1), Vector3(0.0, 0.55, 0.0), wood)
	box(body, Vector3(1.16, 0.12, 1.16), Vector3(0.0, 0.25, 0.0), slat, false)
	box(body, Vector3(1.16, 0.12, 1.16), Vector3(0.0, 0.85, 0.0), slat, false)


static func barrel(parent: Node3D, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.42
	cyl.height = 1.2
	shape.shape = cyl
	shape.position = Vector3(0.0, 0.6, 0.0)
	body.add_child(shape)

	var mesh_node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.42
	mesh.height = 1.2
	mesh_node.mesh = mesh
	mesh_node.position = Vector3(0.0, 0.6, 0.0)
	mesh_node.material_override = material(color, 0.55, 0.5)
	body.add_child(mesh_node)

	var band := material(color.darkened(0.4), 0.6, 0.6)
	for y in [0.3, 0.9]:
		var ring := MeshInstance3D.new()
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = 0.45
		ring_mesh.bottom_radius = 0.45
		ring_mesh.height = 0.1
		ring.mesh = ring_mesh
		ring.position = Vector3(0.0, y, 0.0)
		ring.material_override = band
		body.add_child(ring)


static func fence(parent: Node3D, from: Vector3, to: Vector3) -> void:
	var body := StaticBody3D.new()
	parent.add_child(body)
	var wood := material(Color(0.42, 0.31, 0.2), 0.95)
	var span := from.distance_to(to)
	var mid := (from + to) * 0.5
	var yaw := atan2(to.x - from.x, to.z - from.z)

	body.position = mid
	body.rotation.y = yaw
	box(body, Vector3(0.1, 0.12, span), Vector3(0.0, 1.05, 0.0), wood)
	box(body, Vector3(0.1, 0.12, span), Vector3(0.0, 0.6, 0.0), wood, false)

	var posts := maxi(2, int(span / 2.0))
	for i in posts + 1:
		var z := -span * 0.5 + span * float(i) / float(posts)
		box(body, Vector3(0.14, 1.3, 0.14), Vector3(0.0, 0.65, z), wood, false)


static func street_lamp(parent: Node3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	var metal := material(Color(0.18, 0.19, 0.2), 0.4, 0.8)
	box(body, Vector3(0.36, 0.3, 0.36), Vector3(0.0, 0.15, 0.0), metal)
	box(body, Vector3(0.16, 4.2, 0.16), Vector3(0.0, 2.2, 0.0), metal)
	box(body, Vector3(0.9, 0.14, 0.24), Vector3(0.3, 4.3, 0.0), metal, false)

	var glass := material(Color(1.0, 0.92, 0.72), 0.2)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.85, 0.55)
	glass.emission_energy_multiplier = 1.6
	box(body, Vector3(0.44, 0.22, 0.34), Vector3(0.62, 4.16, 0.0), glass, false)

	var light := OmniLight3D.new()
	light.position = Vector3(0.62, 4.0, 0.0)
	light.omni_range = 9.0
	light.light_energy = 0.55
	light.light_color = Color(1.0, 0.86, 0.6)
	light.shadow_enabled = false
	body.add_child(light)


static func rock(parent: Node3D, pos: Vector3, scale: float, seed_value: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = seed_value
	parent.add_child(body)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = scale * 0.8
	shape.shape = sphere
	shape.position = Vector3(0.0, scale * 0.4, 0.0)
	body.add_child(shape)

	var mesh_node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = scale
	mesh.height = scale * 1.3
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh_node.mesh = mesh
	mesh_node.position = Vector3(0.0, scale * 0.35, 0.0)
	mesh_node.scale = Vector3(1.0, 0.7, 0.85)
	mesh_node.material_override = material(Color(0.42, 0.42, 0.4), 1.0)
	body.add_child(mesh_node)


static func tree(parent: Node3D, pos: Vector3, height: float, leaf_color: Color, seed_value: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = seed_value
	parent.add_child(body)

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.38
	cyl.height = height
	shape.shape = cyl
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(shape)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.26
	trunk_mesh.bottom_radius = 0.46
	trunk_mesh.height = height
	trunk_mesh.radial_segments = 7
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, height * 0.5, 0.0)
	trunk.material_override = material(Color(0.3, 0.22, 0.15), 1.0)
	body.add_child(trunk)

	# Layered canopy reads better than a single sphere.
	var leaf_mat := material(leaf_color, 1.0)
	var layers := 3
	for i in layers:
		var factor := 1.0 - float(i) * 0.26
		var canopy := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = (height * 0.34) * factor
		sphere.height = sphere.radius * 1.7
		sphere.radial_segments = 7
		sphere.rings = 4
		canopy.mesh = sphere
		canopy.position = Vector3(0.0, height * 0.82 + float(i) * height * 0.17, 0.0)
		canopy.rotation.y = seed_value + float(i)
		canopy.material_override = leaf_mat
		body.add_child(canopy)
