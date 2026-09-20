extends Node3D

## Server-authoritative world state: map layout, the golden egg, dropped loot,
## the battle/hunt phase timer and the population-scaled boundary.

const MAP_SEED := 20260920
const MAP_RADIUS := 70.0
const BARRACKS_COUNT := 16
const BARRACKS_RADIUS := 36.0
const PLAZA_RADIUS := 9.0
const EGG_REWARD := 120
const EGG_PICKUP_RANGE := 2.2
const LOOT_PICKUP_RANGE := 2.0
const RESPAWN_DELAY := 3.0
const BOUNDARY_DAMAGE := 18.0

# Phase timing (seconds). Battle windows are deliberately unpredictable.
const HUNT_MIN := 45.0
const HUNT_MAX := 90.0
const BATTLE_MIN := 20.0
const BATTLE_MAX := 60.0

signal state_changed

var battle_active := false
var phase_time_left := 0.0
var boundary_radius := 48.0
var egg_position := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _barracks: Array[Dictionary] = []
var _loot: Dictionary = {}
var _next_loot_id := 1
var _respawn_queue: Dictionary = {}
var building_positions: Array[Vector3] = []
var _egg_node: Node3D
var _boundary_node: MeshInstance3D


func _ready() -> void:
	_rng.seed = MAP_SEED
	_build_map()
	_build_egg_marker()
	_build_boundary_marker()
	if _is_server():
		phase_time_left = _rng.randf_range(HUNT_MIN, HUNT_MAX)
		_relocate_egg()


func _is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


# ---------------------------------------------------------------- map building
# Built identically on every peer from a fixed seed, so nothing needs syncing.

func _build_map() -> void:
	_build_ground()
	_build_plaza()
	_build_roads()
	_build_town()
	_build_street_dressing()
	_build_outskirts()
	_place_barracks()


func _material(color: Color, rough := 0.9) -> StandardMaterial3D:
	return Props.material(color, rough)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(MAP_RADIUS * 2.0, 1.0, MAP_RADIUS * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)

	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(MAP_RADIUS * 2.0, 1.0, MAP_RADIUS * 2.0)
	mesh_node.mesh = mesh
	mesh_node.position = Vector3(0.0, -0.5, 0.0)
	mesh_node.material_override = Props.material(Color(0.23, 0.32, 0.18), 1.0)
	ground.add_child(mesh_node)
	add_child(ground)

	# Patches of dry grass and dirt break up the flat colour.
	for i in 90:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := sqrt(_rng.randf()) * (MAP_RADIUS - 6.0)
		var patch := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		var radius := _rng.randf_range(2.0, 6.5)
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = 0.06
		disc.radial_segments = 18
		patch.mesh = disc
		patch.position = Vector3(cos(angle) * dist, 0.03, sin(angle) * dist)
		var tint := _rng.randf()
		var color := Color(0.26, 0.34, 0.19) if tint < 0.55 else Color(0.3, 0.3, 0.2)
		patch.material_override = Props.material(color.lightened(_rng.randf_range(-0.03, 0.05)), 1.0)
		add_child(patch)


func _build_plaza() -> void:
	var paving := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = PLAZA_RADIUS
	disc.bottom_radius = PLAZA_RADIUS
	disc.height = 0.14
	disc.radial_segments = 24
	paving.mesh = disc
	paving.position = Vector3(0.0, 0.07, 0.0)
	paving.material_override = Props.material(Color(0.34, 0.33, 0.31), 0.98)
	add_child(paving)

	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = PLAZA_RADIUS - 0.35
	torus.outer_radius = PLAZA_RADIUS + 0.2
	rim.mesh = torus
	rim.position = Vector3(0.0, 0.12, 0.0)
	rim.material_override = Props.material(Color(0.4, 0.38, 0.35), 0.95)
	add_child(rim)

	# Monument — the landmark you navigate the whole map by.
	var monument := StaticBody3D.new()
	var stone := Props.material(Color(0.62, 0.59, 0.54), 0.9)
	var stone_dark := Props.material(Color(0.5, 0.47, 0.43), 0.9)
	Props.box(monument, Vector3(4.0, 0.4, 4.0), Vector3(0.0, 0.2, 0.0), stone_dark)
	Props.box(monument, Vector3(3.0, 0.4, 3.0), Vector3(0.0, 0.6, 0.0), stone)
	Props.box(monument, Vector3(2.0, 0.4, 2.0), Vector3(0.0, 1.0, 0.0), stone_dark)
	Props.box(monument, Vector3(1.1, 5.5, 1.1), Vector3(0.0, 3.95, 0.0), stone)

	var gold := Props.material(Color(0.92, 0.76, 0.32), 0.3, 0.8)
	gold.emission_enabled = true
	gold.emission = Color(0.7, 0.55, 0.16)
	gold.emission_energy_multiplier = 1.4
	var finial := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.3
	finial.mesh = sphere
	finial.position = Vector3(0.0, 7.3, 0.0)
	finial.material_override = gold
	monument.add_child(finial)
	add_child(monument)

	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		Props.street_lamp(self, Vector3(cos(angle), 0.0, sin(angle)) * (PLAZA_RADIUS - 1.2))


func _build_roads() -> void:
	var road_mat := Props.material(Color(0.38, 0.35, 0.31), 0.98)
	var kerb_mat := Props.material(Color(0.5, 0.48, 0.44), 0.95)
	for i in 4:
		var yaw := TAU * float(i) / 4.0
		var offset := Vector3(0.0, 0.0, -30.0).rotated(Vector3.UP, yaw)

		var road := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(6.0, 0.12, 50.0)
		road.mesh = mesh
		road.rotation.y = yaw
		road.position = offset + Vector3(0.0, 0.06, 0.0)
		road.material_override = road_mat
		add_child(road)

		for side in [-1.0, 1.0]:
			var kerb := MeshInstance3D.new()
			var kerb_mesh := BoxMesh.new()
			kerb_mesh.size = Vector3(0.4, 0.2, 50.0)
			kerb.mesh = kerb_mesh
			kerb.rotation.y = yaw
			kerb.position = offset + Vector3(side * 3.2, 0.1, 0.0).rotated(Vector3.UP, yaw)
			kerb.material_override = kerb_mat
			add_child(kerb)


func _build_town() -> void:
	var walls := [
		Color(0.76, 0.72, 0.64),
		Color(0.68, 0.58, 0.48),
		Color(0.6, 0.63, 0.65),
		Color(0.78, 0.68, 0.55),
		Color(0.55, 0.52, 0.5),
	]
	var roofs := [
		Color(0.58, 0.32, 0.25),
		Color(0.44, 0.45, 0.5),
		Color(0.64, 0.42, 0.28),
		Color(0.5, 0.52, 0.48),
	]

	for i in 6:
		var angle := TAU * float(i) / 6.0 + 0.26
		var pos := Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(17.5, 19.0)
		var size := Vector3(_rng.randf_range(8.0, 11.0), _rng.randf_range(3.6, 4.2), _rng.randf_range(7.5, 9.5))
		var storeys := 2 if _rng.randf() < 0.4 else 1
		building_positions.append(pos)
		Props.building(self, pos, size, atan2(pos.x, pos.z), walls[i % walls.size()], roofs[i % roofs.size()], storeys)

	for i in 5:
		var angle := TAU * float(i) / 5.0 + 0.9
		var pos := Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(26.0, 28.0)
		var size := Vector3(_rng.randf_range(9.0, 12.0), _rng.randf_range(3.6, 4.4), _rng.randf_range(8.0, 10.0))
		var storeys := 2 if _rng.randf() < 0.5 else 1
		building_positions.append(pos)
		Props.building(self, pos, size, atan2(pos.x, pos.z) + _rng.randf_range(-0.25, 0.25), walls[(i + 2) % walls.size()], roofs[(i + 1) % roofs.size()], storeys)


func _build_street_dressing() -> void:
	# Cover to fight around: crates, barrels, fences and lamps along the streets.
	var barrel_colors := [Color(0.35, 0.42, 0.3), Color(0.45, 0.3, 0.22), Color(0.3, 0.36, 0.45)]

	for pos in building_positions:
		var outward: Vector3 = pos.normalized()
		var across := outward.cross(Vector3.UP)
		var front := pos - outward * 6.5

		if _rng.randf() < 0.75:
			Props.crate(self, front + across * _rng.randf_range(2.0, 3.5), _rng.randf_range(0.0, TAU))
		if _rng.randf() < 0.6:
			Props.crate(self, front + across * _rng.randf_range(2.6, 4.2) + outward * 0.9, _rng.randf_range(0.0, TAU))
		if _rng.randf() < 0.7:
			Props.barrel(self, front - across * _rng.randf_range(2.0, 3.6), barrel_colors[_rng.randi() % barrel_colors.size()])
		if _rng.randf() < 0.5:
			Props.barrel(self, front - across * _rng.randf_range(2.4, 4.0) + outward * 0.8, barrel_colors[_rng.randi() % barrel_colors.size()])
		if _rng.randf() < 0.55:
			Props.street_lamp(self, front + across * _rng.randf_range(-6.0, 6.0) - outward * 2.0)
		if _rng.randf() < 0.5:
			var a := pos + across * 6.0 + outward * 2.0
			var b := pos + across * 6.0 - outward * 5.0
			Props.fence(self, a, b)


func _build_outskirts() -> void:
	var leaf_colors := [
		Color(0.16, 0.31, 0.16),
		Color(0.2, 0.36, 0.18),
		Color(0.24, 0.33, 0.15),
		Color(0.14, 0.27, 0.17),
	]

	for i in 70:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(40.0, MAP_RADIUS - 6.0)
		Props.tree(
			self,
			Vector3(cos(angle) * dist, 0.0, sin(angle) * dist),
			_rng.randf_range(4.5, 8.5),
			leaf_colors[_rng.randi() % leaf_colors.size()],
			_rng.randf_range(0.0, TAU)
		)

	# A few clumps closer in, as cover between the town and the treeline.
	for i in 14:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(31.0, 39.0)
		Props.tree(
			self,
			Vector3(cos(angle) * dist, 0.0, sin(angle) * dist),
			_rng.randf_range(4.0, 6.5),
			leaf_colors[_rng.randi() % leaf_colors.size()],
			_rng.randf_range(0.0, TAU)
		)

	for i in 26:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(20.0, MAP_RADIUS - 8.0)
		Props.rock(self, Vector3(cos(angle) * dist, 0.0, sin(angle) * dist), _rng.randf_range(0.5, 1.4), _rng.randf_range(0.0, TAU))


func _place_barracks() -> void:
	for i in BARRACKS_COUNT:
		var angle := TAU * float(i) / float(BARRACKS_COUNT)
		var pos := Vector3(cos(angle), 0.0, sin(angle)) * BARRACKS_RADIUS

		var pad := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(2.8, 0.3, 2.8)
		pad.mesh = box_mesh
		pad.position = pos + Vector3(0.0, 0.15, 0.0)
		var mat := Props.material(Color(0.82, 0.67, 0.3), 0.5, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.31, 0.1)
		mat.emission_energy_multiplier = 1.2
		pad.material_override = mat
		add_child(pad)

		var glow := OmniLight3D.new()
		glow.position = pos + Vector3(0.0, 1.0, 0.0)
		glow.omni_range = 5.0
		glow.light_energy = 0.45
		glow.light_color = Color(1.0, 0.82, 0.45)
		glow.shadow_enabled = false
		add_child(glow)

		_barracks.append({"pos": pos, "owner": 0})


func _random_point(radius: float) -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var dist := sqrt(_rng.randf()) * radius
	return Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _build_egg_marker() -> void:
	_egg_node = Node3D.new()
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.4
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.76, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.6, 0.1)
	mat.emission_energy_multiplier = 1.6
	mesh.material_override = mat
	mesh.position = Vector3(0.0, 1.0, 0.0)
	_egg_node.add_child(mesh)

	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.06
	beam_mesh.bottom_radius = 0.3
	beam_mesh.height = 40.0
	beam.mesh = beam_mesh
	beam.position = Vector3(0.0, 20.0, 0.0)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.16)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = beam_mat
	_egg_node.add_child(beam)

	add_child(_egg_node)


func _build_boundary_marker() -> void:
	# An open wall, not a dome: capped ends would enclose the whole map in a
	# translucent shell and tint everything behind it.
	_boundary_node = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 26.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 64
	_boundary_node.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.85, 1.0, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.6, 0.8)
	mat.emission_energy_multiplier = 0.4
	_boundary_node.material_override = mat
	_boundary_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boundary_node.position = Vector3(0.0, 13.0, 0.0)
	add_child(_boundary_node)


func _process(delta: float) -> void:
	if _boundary_node != null:
		_boundary_node.scale = Vector3(boundary_radius, 1.0, boundary_radius)
		_fade_boundary()
	if _egg_node != null:
		_egg_node.rotate_y(delta * 1.2)

	if not _is_server():
		return

	phase_time_left -= delta
	if phase_time_left <= 0.0:
		_advance_phase()

	_update_boundary()
	_check_pickups(delta)
	_tick_respawns(delta)


# ------------------------------------------------------------------- phases

func _fade_boundary() -> void:
	# The wall is only drawn when someone is close to it, so it never hangs over
	# the map as a translucent veil.
	var mat: StandardMaterial3D = _boundary_node.material_override
	if mat == null:
		return
	var nearest := 9999.0
	for player in _players():
		if player.is_local:
			var flat := Vector3(player.global_position.x, 0.0, player.global_position.z)
			nearest = minf(nearest, boundary_radius - flat.length())
	var alpha := clampf(inverse_lerp(26.0, 4.0, nearest), 0.0, 1.0) * 0.28
	mat.albedo_color = Color(0.4, 0.85, 1.0, alpha)


func _advance_phase() -> void:
	battle_active = not battle_active
	if battle_active:
		phase_time_left = _rng.randf_range(BATTLE_MIN, BATTLE_MAX)
	else:
		phase_time_left = _rng.randf_range(HUNT_MIN, HUNT_MAX)
	_sync_phase.rpc(battle_active, phase_time_left)


@rpc("authority", "call_local", "reliable")
func _sync_phase(active: bool, time_left: float) -> void:
	battle_active = active
	phase_time_left = time_left
	state_changed.emit()


func _update_boundary() -> void:
	var count := maxi(1, _players().size())
	# Must always enclose the barracks ring and its overflow ring, or players
	# spawn outside the boundary and bleed out.
	var target := clampf(48.0 + float(count) * 1.6, 48.0, MAP_RADIUS - 5.0)
	if absf(target - boundary_radius) > 0.5:
		boundary_radius = target
		_sync_boundary.rpc(boundary_radius)


@rpc("authority", "call_local", "reliable")
func _sync_boundary(radius: float) -> void:
	boundary_radius = radius
	state_changed.emit()


# --------------------------------------------------------------- egg & loot

func _relocate_egg() -> void:
	var pos := _random_point(maxf(boundary_radius - 6.0, 10.0))
	_set_egg.rpc(pos)


@rpc("authority", "call_local", "reliable")
func _set_egg(pos: Vector3) -> void:
	egg_position = pos
	if _egg_node != null:
		_egg_node.position = pos
	state_changed.emit()


func _check_pickups(delta: float) -> void:
	for player in _players():
		if not player.alive:
			continue

		var flat_player := Vector3(player.global_position.x, 0.0, player.global_position.z)

		# Boundary damage — step outside the ring and you bleed out.
		if flat_player.length() > boundary_radius:
			_damage(player, BOUNDARY_DAMAGE * delta, 0)

		if not is_instance_valid(player) or not player.alive:
			continue

		if flat_player.distance_to(Vector3(egg_position.x, 0.0, egg_position.z)) < EGG_PICKUP_RANGE:
			player.coins += EGG_REWARD
			_push_stats(player)
			_announce.rpc("%s found the golden egg (+%d)" % [player.player_name, EGG_REWARD])
			_relocate_egg()

		for loot_id in _loot.keys():
			var loot: Dictionary = _loot[loot_id]
			var loot_pos: Vector3 = loot["pos"]
			if flat_player.distance_to(Vector3(loot_pos.x, 0.0, loot_pos.z)) < LOOT_PICKUP_RANGE:
				player.coins += int(loot["amount"])
				_push_stats(player)
				_announce.rpc("%s collected %d coins" % [player.player_name, int(loot["amount"])])
				_loot.erase(loot_id)
				_remove_loot.rpc(loot_id)


func _drop_loot(pos: Vector3, amount: int) -> void:
	if amount <= 0:
		return
	var loot_id := _next_loot_id
	_next_loot_id += 1
	_loot[loot_id] = {"pos": pos, "amount": amount}
	_spawn_loot.rpc(loot_id, pos, amount)


@rpc("authority", "call_local", "reliable")
func _spawn_loot(loot_id: int, pos: Vector3, amount: int) -> void:
	var node := MeshInstance3D.new()
	node.name = "Loot_%d" % loot_id
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	node.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.8, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.55, 0.1)
	node.material_override = mat
	node.position = pos + Vector3(0.0, 0.4, 0.0)
	add_child(node)

	var label := Label3D.new()
	label.text = "%d" % amount
	label.position = Vector3(0.0, 0.8, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.006
	node.add_child(label)


@rpc("authority", "call_local", "reliable")
func _remove_loot(loot_id: int) -> void:
	var node := get_node_or_null("Loot_%d" % loot_id)
	if node != null:
		node.queue_free()


# ---------------------------------------------------------------- combat

@rpc("any_peer", "reliable")
func request_hit(target_id: int, damage: float) -> void:
	if not _is_server() or not battle_active:
		return
	var shooter_id := multiplayer.get_remote_sender_id()
	if shooter_id == target_id:
		return
	var target := _player_by_id(target_id)
	if target == null or not target.alive:
		return
	var shooter := _player_by_id(shooter_id)
	if shooter != null and not shooter.alive:
		return
	_damage(target, damage, shooter_id)


func _damage(player: Node, amount: float, killer_id: int) -> void:
	player.health -= amount
	if player.health > 0.0:
		_push_stats(player)
		return

	# Death: everything carried scatters on the ground where they fell.
	var dropped: int = player.coins
	player.coins = 0
	player.health = 0.0
	player.alive = false
	_push_stats(player)
	_drop_loot(player.global_position, dropped)
	_respawn_queue[player.peer_id] = RESPAWN_DELAY

	var killer := _player_by_id(killer_id)
	if killer != null:
		_announce.rpc("%s was killed by %s — %d coins dropped" % [player.player_name, killer.player_name, dropped])
	else:
		_announce.rpc("%s died outside the boundary — %d coins dropped" % [player.player_name, dropped])


func _tick_respawns(delta: float) -> void:
	for id in _respawn_queue.keys():
		_respawn_queue[id] -= delta
		if _respawn_queue[id] > 0.0:
			continue
		_respawn_queue.erase(id)
		var player := _player_by_id(id)
		if player == null:
			continue
		player.health = 100.0
		player.alive = true
		var spawn := spawn_point_for(id)
		_push_stats(player)
		_force_position.rpc(id, spawn)


@rpc("authority", "call_local", "reliable")
func _force_position(id: int, pos: Vector3) -> void:
	var player := _player_by_id(id)
	if player != null:
		player.teleport(pos)


func _push_stats(player: Node) -> void:
	_sync_stats.rpc(player.peer_id, player.health, player.coins, player.alive)


@rpc("authority", "call_local", "reliable")
func _sync_stats(id: int, health: float, coins: int, alive: bool) -> void:
	var player := _player_by_id(id)
	if player != null:
		player.apply_stats(health, coins, alive)
		state_changed.emit()


@rpc("authority", "call_local", "reliable")
func _announce(message: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.push_feed(message)


# ---------------------------------------------------------------- barracks

func spawn_point_for(id: int) -> Vector3:
	for entry in _barracks:
		if entry["owner"] == id:
			return entry["pos"] + Vector3(0.0, 1.0, 0.0)
	return claim_barracks(id)


func claim_barracks(id: int) -> Vector3:
	for entry in _barracks:
		if entry["owner"] == 0:
			entry["owner"] = id
			return entry["pos"] + Vector3(0.0, 1.0, 0.0)
	# Supply is unlimited: if the ring is full, add another further out.
	var angle := _rng.randf_range(0.0, TAU)
	var pos := Vector3(cos(angle), 0.0, sin(angle)) * 42.0
	_barracks.append({"pos": pos, "owner": id})
	return pos + Vector3(0.0, 1.0, 0.0)


func release_barracks(id: int) -> void:
	for entry in _barracks:
		if entry["owner"] == id:
			entry["owner"] = 0


# ----------------------------------------------------------------- helpers

func _players() -> Array:
	return get_tree().get_nodes_in_group("players")


func _player_by_id(id: int) -> Node:
	for player in _players():
		if player.peer_id == id:
			return player
	return null
