extends Node3D

## Server-authoritative world state: map layout, the golden egg, dropped loot,
## the battle/hunt phase timer and the population-scaled boundary.

const MAP_SEED := 20260920
const MAP_RADIUS := 70.0
const BARRACKS_COUNT := 16
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
var boundary_radius := 30.0
var egg_position := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _barracks: Array[Dictionary] = []
var _loot: Dictionary = {}
var _next_loot_id := 1
var _respawn_queue: Dictionary = {}
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
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(MAP_RADIUS * 2.0, 1.0, MAP_RADIUS * 2.0)
	ground_shape.shape = box
	ground_shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(ground_shape)

	var ground_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(MAP_RADIUS * 2.0, 1.0, MAP_RADIUS * 2.0)
	ground_mesh.mesh = plane
	ground_mesh.position = Vector3(0.0, -0.5, 0.0)
	ground_mesh.material_override = _material(Color(0.24, 0.42, 0.26))
	ground.add_child(ground_mesh)
	add_child(ground)

	_scatter_trees(110)
	_place_buildings(9)
	_place_barracks()


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


func _scatter_trees(count: int) -> void:
	for i in count:
		var pos := _random_point(MAP_RADIUS - 6.0)
		if pos.length() < 12.0:
			continue  # keep the middle clear as a natural meeting ground
		var height := _rng.randf_range(3.5, 6.5)

		var trunk := StaticBody3D.new()
		var trunk_shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.35
		cyl.height = height
		trunk_shape.shape = cyl
		trunk_shape.position = Vector3(0.0, height * 0.5, 0.0)
		trunk.add_child(trunk_shape)

		var trunk_mesh := MeshInstance3D.new()
		var trunk_cyl := CylinderMesh.new()
		trunk_cyl.top_radius = 0.3
		trunk_cyl.bottom_radius = 0.4
		trunk_cyl.height = height
		trunk_mesh.mesh = trunk_cyl
		trunk_mesh.position = Vector3(0.0, height * 0.5, 0.0)
		trunk_mesh.material_override = _material(Color(0.32, 0.22, 0.14))
		trunk.add_child(trunk_mesh)

		var leaves := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = _rng.randf_range(1.6, 2.6)
		sphere.height = sphere.radius * 2.0
		leaves.mesh = sphere
		leaves.position = Vector3(0.0, height + 0.6, 0.0)
		leaves.material_override = _material(Color(0.16, 0.38, 0.2))
		trunk.add_child(leaves)

		trunk.position = pos
		add_child(trunk)


func _place_buildings(count: int) -> void:
	for i in count:
		var pos := _random_point(MAP_RADIUS - 14.0)
		if pos.length() < 16.0:
			pos = pos.normalized() * 18.0
		var size := Vector3(
			_rng.randf_range(6.0, 12.0),
			_rng.randf_range(4.0, 8.0),
			_rng.randf_range(6.0, 12.0)
		)

		var building := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = Vector3(0.0, size.y * 0.5, 0.0)
		building.add_child(shape)

		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh.mesh = box_mesh
		mesh.position = Vector3(0.0, size.y * 0.5, 0.0)
		mesh.material_override = _material(Color(0.55, 0.5, 0.44))
		building.add_child(mesh)

		building.position = pos
		building.rotation.y = _rng.randf_range(0.0, TAU)
		add_child(building)


func _place_barracks() -> void:
	# Spawn points arranged in a ring. Supply is effectively unlimited: they are
	# only a place to appear, they store nothing.
	for i in BARRACKS_COUNT:
		var angle := TAU * float(i) / float(BARRACKS_COUNT)
		var pos := Vector3(cos(angle), 0.0, sin(angle)) * 24.0

		var marker := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(2.4, 0.3, 2.4)
		marker.mesh = box_mesh
		marker.position = pos + Vector3(0.0, 0.15, 0.0)
		marker.material_override = _material(Color(0.75, 0.62, 0.3))
		add_child(marker)

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
	_boundary_node = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 24.0
	_boundary_node.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.8, 1.0, 0.12)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_boundary_node.material_override = mat
	_boundary_node.position = Vector3(0.0, 12.0, 0.0)
	add_child(_boundary_node)


func _process(delta: float) -> void:
	if _boundary_node != null:
		_boundary_node.scale = Vector3(boundary_radius, 1.0, boundary_radius)
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
	var target := clampf(20.0 + float(count) * 3.0, 22.0, MAP_RADIUS - 5.0)
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
	var pos := Vector3(cos(angle), 0.0, sin(angle)) * 32.0
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
