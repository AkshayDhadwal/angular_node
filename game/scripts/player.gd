extends CharacterBody3D

const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.5
const JUMP_VELOCITY := 7.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.0022
const SYNC_HZ := 20.0
const SHOT_DAMAGE := 34.0
const SHOT_RANGE := 120.0
const SHOT_COOLDOWN := 0.6

# KayKit Adventurers (CC0) — see assets/KAYKIT-LICENSE.txt
const CHARACTER_MODELS := [
	preload("res://assets/characters/Knight.glb"),
	preload("res://assets/characters/Rogue.glb"),
	preload("res://assets/characters/Mage.glb"),
	preload("res://assets/characters/Barbarian.glb"),
]
const WEAPON_MODEL := preload("res://assets/weapons/crossbow_2handed.gltf")

const ANIM_IDLE := "2H_Ranged_Aiming"
const ANIM_WALK := "Walking_A"
const ANIM_RUN := "Running_A"
const ANIM_JUMP := "Jump_Idle"
const ANIM_SHOOT := "2H_Ranged_Shoot"
const ANIM_DEATH := "Death_A"

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
var _prev_pos := Vector3.ZERO
var _observed_speed := 0.0
var _current_anim := ""
var _action_lock := 0.0

var spring: SpringArm3D
var camera: Camera3D
var rig: Node3D
var model: Node3D
var anim: AnimationPlayer
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


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.8, 0.0)
	add_child(shape)


func _build_character() -> void:
	rig = Node3D.new()
	add_child(rig)

	var scene: PackedScene = CHARACTER_MODELS[peer_id % CHARACTER_MODELS.size()]
	model = scene.instantiate()
	# The GLTF rig faces +Z; Godot treats -Z as forward.
	model.rotation.y = PI
	rig.add_child(model)

	anim = _find_animation_player(model)
	_hide_stock_gear(model)
	_attach_weapon()

	name_label = Label3D.new()
	name_label.text = player_name
	name_label.position = Vector3(0.0, 2.0, 0.0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.font_size = 44
	name_label.pixel_size = 0.0042
	name_label.outline_size = 10
	add_child(name_label)


func _hide_stock_gear(node: Node) -> void:
	# The pack ships every sword and shield visible in the hand sockets at once;
	# they must be hidden or the character carries the whole armoury.
	var parent := node.get_parent()
	if node is MeshInstance3D and parent != null and "handslot" in String(parent.name):
		node.visible = false
	for child in node.get_children():
		_hide_stock_gear(child)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _attach_weapon() -> void:
	var skeleton := _find_skeleton(model)
	if skeleton == null:
		return
	# The rig ships dedicated weapon sockets rather than parenting to the hand.
	var bone := skeleton.find_bone("handslot.r")
	if bone == -1:
		bone = skeleton.find_bone("hand.r")
	if bone == -1:
		return

	var attachment := BoneAttachment3D.new()
	attachment.bone_idx = bone
	skeleton.add_child(attachment)
	attachment.add_child(WEAPON_MODEL.instantiate())


func _build_camera() -> void:
	spring = SpringArm3D.new()
	spring.position = Vector3(0.0, 1.45, 0.0)
	spring.spring_length = 5.0
	spring.margin = 0.3
	add_child(spring)

	camera = Camera3D.new()
	# Over-the-shoulder so the player's own body doesn't sit on the crosshair.
	camera.position = Vector3(0.8, 0.0, 0.0)
	camera.current = true
	spring.add_child(camera)


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
	_action_lock = maxf(0.0, _action_lock - delta)

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
		var travelled := global_position - _prev_pos
		_observed_speed = Vector2(travelled.x, travelled.z).length() / delta
		_prev_pos = global_position

	_update_animation()


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

func _play(anim_name: String, blend := 0.15) -> void:
	if anim == null or _current_anim == anim_name or not anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	anim.play(anim_name, blend)


func _play_action(anim_name: String, duration: float) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_action_lock = duration
	anim.play(anim_name, 0.08)


func _update_animation() -> void:
	if anim == null:
		return

	if not alive:
		_play(ANIM_DEATH, 0.2)
		return

	if _action_lock > 0.0:
		return

	if is_local and not is_on_floor():
		_play(ANIM_JUMP)
	elif _observed_speed > WALK_SPEED + 1.0:
		_play(ANIM_RUN)
	elif _observed_speed > 0.6:
		_play(ANIM_WALK)
	else:
		_play(ANIM_IDLE, 0.25)


# ------------------------------------------------------------------ combat

func _try_shoot() -> void:
	if not alive or _shot_cooldown > 0.0 or camera == null:
		return
	var world := get_parent()
	if world == null or not world.get("battle_active"):
		return

	_shot_cooldown = SHOT_COOLDOWN
	_shoot_effect.rpc()

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


@rpc("any_peer", "call_local", "reliable")
func _shoot_effect() -> void:
	_play_action(ANIM_SHOOT, 0.5)


@rpc("any_peer", "unreliable_ordered", "call_remote")
func _apply_state(pos: Vector3, new_yaw: float) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_target_pos = pos
	_target_yaw = new_yaw


func apply_stats(new_health: float, new_coins: int, is_alive: bool) -> void:
	if alive != is_alive:
		# Force the animation state machine to re-evaluate on death or respawn.
		_current_anim = ""
		_action_lock = 0.0
	health = new_health
	coins = new_coins
	alive = is_alive
	if name_label != null:
		name_label.visible = is_alive


func teleport(pos: Vector3) -> void:
	global_position = pos
	_target_pos = pos
	_prev_pos = pos
	velocity = Vector3.ZERO
