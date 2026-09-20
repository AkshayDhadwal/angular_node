extends CharacterBody3D

const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.5
const JUMP_VELOCITY := 7.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.0022
const SYNC_HZ := 20.0
const SHOT_DAMAGE := 34.0
const SHOT_RANGE := 120.0
const SHOT_COOLDOWN := 0.35

var peer_id := 1
var player_name := "Player"
var is_local := false

var health := 100.0
var coins := 0
var alive := true

var yaw := 0.0
var pitch := -0.25

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _sync_accum := 0.0
var _shot_cooldown := 0.0
var _anim_time := 0.0
var _prev_pos := Vector3.ZERO
var _observed_speed := 0.0

var spring: SpringArm3D
var camera: Camera3D
var rig: Node3D
var torso: MeshInstance3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var name_label: Label3D


func _ready() -> void:
	add_to_group("players")
	_build_collision()
	_build_character()
	is_local = peer_id == multiplayer.get_unique_id()
	_target_pos = global_position
	_prev_pos = global_position
	_target_yaw = rotation.y
	yaw = rotation.y
	if is_local:
		_build_camera()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_peer_id() -> int:
	return peer_id


# --------------------------------------------------------------- appearance

func _material(color: Color, rough := 0.85) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat


func _part(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	return node


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)


func _build_character() -> void:
	rig = Node3D.new()
	add_child(rig)

	var base_color := _color_for_peer(peer_id)
	var shirt := _material(base_color, 0.95)
	var sleeve := _material(base_color.darkened(0.18), 0.95)
	var skin := _material(Color(0.8, 0.62, 0.47), 0.85)
	var trousers := _material(Color(0.19, 0.21, 0.27), 0.95)
	var boots := _material(Color(0.12, 0.11, 0.12), 0.8)
	var hair := _material(Color(0.13, 0.1, 0.08), 0.95)
	var belt := _material(Color(0.24, 0.18, 0.13), 0.8)

	# Torso: narrower than the hips at the waist, wider at the shoulders.
	torso = _part(Vector3(0.44, 0.52, 0.26), Vector3(0.0, 1.18, 0.0), shirt)
	rig.add_child(torso)
	rig.add_child(_part(Vector3(0.5, 0.17, 0.28), Vector3(0.0, 1.4, 0.0), shirt))
	rig.add_child(_part(Vector3(0.42, 0.14, 0.26), Vector3(0.0, 0.95, 0.0), belt))
	rig.add_child(_part(Vector3(0.4, 0.14, 0.25), Vector3(0.0, 0.86, 0.0), trousers))

	# Head on its own pivot
	head = Node3D.new()
	head.position = Vector3(0.0, 1.54, 0.0)
	rig.add_child(head)
	head.add_child(_part(Vector3(0.15, 0.13, 0.15), Vector3(0.0, 0.05, 0.0), skin))
	head.add_child(_part(Vector3(0.3, 0.3, 0.29), Vector3(0.0, 0.26, 0.0), skin))
	head.add_child(_part(Vector3(0.32, 0.1, 0.31), Vector3(0.0, 0.44, 0.0), hair))
	head.add_child(_part(Vector3(0.33, 0.12, 0.06), Vector3(0.0, 0.33, -0.14), hair))
	var eye := _material(Color(0.07, 0.07, 0.09), 0.4)
	head.add_child(_part(Vector3(0.055, 0.055, 0.02), Vector3(-0.07, 0.27, -0.152), eye))
	head.add_child(_part(Vector3(0.055, 0.055, 0.02), Vector3(0.07, 0.27, -0.152), eye))

	# Arms: shoulder pivot, then an elbow pivot carrying the forearm.
	arm_l = Node3D.new()
	arm_l.position = Vector3(-0.31, 1.44, 0.0)
	rig.add_child(arm_l)
	arm_l.add_child(_part(Vector3(0.15, 0.4, 0.16), Vector3(0.0, -0.2, 0.0), sleeve))
	elbow_l = Node3D.new()
	elbow_l.position = Vector3(0.0, -0.4, 0.0)
	arm_l.add_child(elbow_l)
	elbow_l.add_child(_part(Vector3(0.13, 0.36, 0.14), Vector3(0.0, -0.18, 0.0), sleeve))
	elbow_l.add_child(_part(Vector3(0.14, 0.15, 0.15), Vector3(0.0, -0.42, 0.0), skin))

	arm_r = Node3D.new()
	arm_r.position = Vector3(0.31, 1.44, 0.0)
	rig.add_child(arm_r)
	arm_r.add_child(_part(Vector3(0.15, 0.4, 0.16), Vector3(0.0, -0.2, 0.0), sleeve))
	elbow_r = Node3D.new()
	elbow_r.position = Vector3(0.0, -0.4, 0.0)
	arm_r.add_child(elbow_r)
	elbow_r.add_child(_part(Vector3(0.13, 0.36, 0.14), Vector3(0.0, -0.18, 0.0), sleeve))
	elbow_r.add_child(_part(Vector3(0.14, 0.15, 0.15), Vector3(0.0, -0.42, 0.0), skin))

	# Legs: hip pivot, then a knee pivot carrying the shin and boot.
	leg_l = Node3D.new()
	leg_l.position = Vector3(-0.12, 0.9, 0.0)
	rig.add_child(leg_l)
	leg_l.add_child(_part(Vector3(0.18, 0.44, 0.19), Vector3(0.0, -0.22, 0.0), trousers))
	knee_l = Node3D.new()
	knee_l.position = Vector3(0.0, -0.44, 0.0)
	leg_l.add_child(knee_l)
	knee_l.add_child(_part(Vector3(0.16, 0.42, 0.17), Vector3(0.0, -0.21, 0.0), trousers))
	knee_l.add_child(_part(Vector3(0.19, 0.13, 0.27), Vector3(0.0, -0.45, -0.04), boots))

	leg_r = Node3D.new()
	leg_r.position = Vector3(0.12, 0.9, 0.0)
	rig.add_child(leg_r)
	leg_r.add_child(_part(Vector3(0.18, 0.44, 0.19), Vector3(0.0, -0.22, 0.0), trousers))
	knee_r = Node3D.new()
	knee_r.position = Vector3(0.0, -0.44, 0.0)
	leg_r.add_child(knee_r)
	knee_r.add_child(_part(Vector3(0.16, 0.42, 0.17), Vector3(0.0, -0.21, 0.0), trousers))
	knee_r.add_child(_part(Vector3(0.19, 0.13, 0.27), Vector3(0.0, -0.45, -0.04), boots))

	name_label = Label3D.new()
	name_label.text = player_name
	name_label.position = Vector3(0.0, 2.3, 0.0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.font_size = 44
	name_label.pixel_size = 0.0042
	name_label.outline_size = 10
	add_child(name_label)


func _build_camera() -> void:
	spring = SpringArm3D.new()
	spring.position = Vector3(0.0, 1.7, 0.0)
	spring.spring_length = 5.0
	spring.margin = 0.3
	add_child(spring)

	camera = Camera3D.new()
	# Over-the-shoulder so the player's own body doesn't sit on the crosshair.
	camera.position = Vector3(0.8, 0.0, 0.0)
	camera.current = true
	spring.add_child(camera)


func _color_for_peer(id: int) -> Color:
	var hue := fmod(float(id) * 0.191, 1.0)
	return Color.from_hsv(hue, 0.6, 0.85)


func set_display_name(value: String) -> void:
	player_name = value
	if name_label != null:
		name_label.text = value


# ------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.2, 0.5)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_try_shoot()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_shot_cooldown = maxf(0.0, _shot_cooldown - delta)

	if is_local:
		if alive:
			_move_local(delta)
		_sync_accum += delta
		if _sync_accum >= 1.0 / SYNC_HZ:
			_sync_accum = 0.0
			_apply_state.rpc(global_position, yaw)
	else:
		var weight := clampf(delta * 12.0, 0.0, 1.0)
		global_position = global_position.lerp(_target_pos, weight)
		rotation.y = lerp_angle(rotation.y, _target_yaw, weight)

	if delta > 0.0:
		var travelled := (global_position - _prev_pos)
		_observed_speed = Vector2(travelled.x, travelled.z).length() / delta
		_prev_pos = global_position
	_animate(delta)


func _move_local(delta: float) -> void:
	rotation.y = yaw
	if spring != null:
		spring.rotation.x = pitch

	if is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta

	var wish := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		wish.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		wish.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		wish.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		wish.x += 1.0

	var speed := SPRINT_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	if wish != Vector3.ZERO:
		var dir := transform.basis * wish.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 5.0 * delta)

	move_and_slide()


# --------------------------------------------------------------- animation

func _animate(delta: float) -> void:
	if rig == null:
		return

	var moving := _observed_speed > 0.6
	var stride_rate := 5.0 + clampf(_observed_speed, 0.0, 10.0) * 0.85
	_anim_time += delta * (stride_rate if moving else 1.8)

	var settle := clampf(delta * 10.0, 0.0, 1.0)

	if moving:
		var amount := clampf(_observed_speed / WALK_SPEED, 0.25, 1.5)
		var swing := sin(_anim_time) * 0.8 * amount

		arm_l.rotation.x = swing
		arm_r.rotation.x = -swing
		# Elbows stay slightly bent and tuck further on the back swing.
		elbow_l.rotation.x = -0.25 - maxf(0.0, -swing) * 0.55
		elbow_r.rotation.x = -0.25 - maxf(0.0, swing) * 0.55

		leg_l.rotation.x = -swing
		leg_r.rotation.x = swing
		knee_l.rotation.x = -maxf(0.0, swing) * 0.95
		knee_r.rotation.x = -maxf(0.0, -swing) * 0.95

		torso.position.y = 1.18 + absf(sin(_anim_time)) * 0.035
		torso.rotation.z = sin(_anim_time) * 0.035
		rig.rotation.x = -clampf(_observed_speed / SPRINT_SPEED, 0.0, 1.0) * 0.09
	else:
		arm_l.rotation.x = lerp_angle(arm_l.rotation.x, 0.0, settle)
		arm_r.rotation.x = lerp_angle(arm_r.rotation.x, 0.0, settle)
		elbow_l.rotation.x = lerp_angle(elbow_l.rotation.x, -0.18, settle)
		elbow_r.rotation.x = lerp_angle(elbow_r.rotation.x, -0.18, settle)
		leg_l.rotation.x = lerp_angle(leg_l.rotation.x, 0.0, settle)
		leg_r.rotation.x = lerp_angle(leg_r.rotation.x, 0.0, settle)
		knee_l.rotation.x = lerp_angle(knee_l.rotation.x, 0.0, settle)
		knee_r.rotation.x = lerp_angle(knee_r.rotation.x, 0.0, settle)
		torso.position.y = 1.18 + sin(_anim_time) * 0.012
		torso.rotation.z = lerp_angle(torso.rotation.z, 0.0, settle)
		rig.rotation.x = lerp_angle(rig.rotation.x, 0.0, settle)

	if head != null:
		# Only a hint of the aim direction — a full pitch match looks broken.
		var look := pitch * 0.3 if is_local else 0.0
		head.rotation.x = lerp_angle(head.rotation.x, clampf(look, -0.2, 0.15), settle)


# ------------------------------------------------------------------ combat

func _try_shoot() -> void:
	if not alive or _shot_cooldown > 0.0 or camera == null:
		return
	var world := get_parent()
	if world == null or not world.get("battle_active"):
		return

	_shot_cooldown = SHOT_COOLDOWN

	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * SHOT_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return

	var collider = hit.get("collider")
	if collider != null and collider.has_method("get_peer_id"):
		world.request_hit.rpc_id(1, collider.get_peer_id(), SHOT_DAMAGE)


@rpc("any_peer", "unreliable_ordered", "call_remote")
func _apply_state(pos: Vector3, new_yaw: float) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_target_pos = pos
	_target_yaw = new_yaw


func apply_stats(new_health: float, new_coins: int, is_alive: bool) -> void:
	health = new_health
	coins = new_coins
	alive = is_alive
	if rig != null:
		rig.visible = is_alive
	if name_label != null:
		name_label.visible = is_alive


func teleport(pos: Vector3) -> void:
	global_position = pos
	_target_pos = pos
	_prev_pos = pos
	velocity = Vector3.ZERO
