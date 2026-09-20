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

var spring: SpringArm3D
var camera: Camera3D
var body_mesh: MeshInstance3D
var name_label: Label3D


func _ready() -> void:
	add_to_group("players")
	_build_body()
	is_local = peer_id == multiplayer.get_unique_id()
	_target_pos = global_position
	_target_yaw = rotation.y
	yaw = rotation.y
	if is_local:
		_build_camera()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_peer_id() -> int:
	return peer_id


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)

	body_mesh = MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.4
	capsule_mesh.height = 1.8
	body_mesh.mesh = capsule_mesh
	body_mesh.position = Vector3(0.0, 0.9, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color_for_peer(peer_id)
	body_mesh.material_override = mat
	add_child(body_mesh)

	# A small snout so facing direction is readable in third person.
	var snout := MeshInstance3D.new()
	var snout_mesh := BoxMesh.new()
	snout_mesh.size = Vector3(0.22, 0.22, 0.4)
	snout.mesh = snout_mesh
	snout.position = Vector3(0.0, 1.45, -0.45)
	snout.material_override = mat
	add_child(snout)

	name_label = Label3D.new()
	name_label.text = player_name
	name_label.position = Vector3(0.0, 2.2, 0.0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.font_size = 48
	name_label.pixel_size = 0.005
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
	return Color.from_hsv(hue, 0.55, 0.9)


func set_display_name(value: String) -> void:
	player_name = value
	if name_label != null:
		name_label.text = value


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
	if body_mesh != null:
		body_mesh.visible = is_alive
	visible = is_alive or is_local


func teleport(pos: Vector3) -> void:
	global_position = pos
	_target_pos = pos
	velocity = Vector3.ZERO
