extends Node3D

## Bootstrap: lobby menu, ENet host/join, and player spawn replication.

const PORT := 8910
const MAX_PLAYERS := 16

const WorldScene := preload("res://scenes/world.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const HudScene := preload("res://scenes/hud.tscn")

var world: Node3D
var hud: CanvasLayer
var menu: CanvasLayer
var name_input: LineEdit
var ip_input: LineEdit
var status_label: Label

var local_name := "Player"
var players: Dictionary = {}
var player_names: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	_build_environment()
	_build_menu()

	# Headless dedicated server: godot --headless -- --server
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		_host()
	elif "--client" in OS.get_cmdline_user_args():
		_join()


func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-1.0, -0.6, 0.0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.6
	env.environment = environment
	add_child(env)


# ------------------------------------------------------------------- lobby

func _build_menu() -> void:
	menu = CanvasLayer.new()
	add_child(menu)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.11, 0.09)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "GOLDEN EGG"
	title.add_theme_font_size_override("font_size", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Find the egg. Survive the battle window. Don't lose your coins."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(_spacer(16))

	name_input = LineEdit.new()
	name_input.placeholder_text = "Your name"
	name_input.text = "Player%d" % (randi() % 900 + 100)
	name_input.custom_minimum_size = Vector2(320, 38)
	box.add_child(name_input)

	var host_button := Button.new()
	host_button.text = "Host a game"
	host_button.custom_minimum_size = Vector2(320, 44)
	host_button.pressed.connect(_host)
	box.add_child(host_button)

	box.add_child(_spacer(10))

	ip_input = LineEdit.new()
	ip_input.placeholder_text = "Host address (blank = 127.0.0.1)"
	ip_input.custom_minimum_size = Vector2(320, 38)
	box.add_child(ip_input)

	var join_button := Button.new()
	join_button.text = "Join a game"
	join_button.custom_minimum_size = Vector2(320, 44)
	join_button.pressed.connect(_join)
	box.add_child(join_button)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size = Vector2(320, 24)
	box.add_child(status_label)

	var help := Label.new()
	help.text = "WASD move · Shift sprint · Space jump · Mouse look · Click shoot (battle only) · Esc release cursor"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(help)


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _chosen_name() -> String:
	var value := name_input.text.strip_edges() if name_input != null else ""
	return value if value != "" else "Player"


func _host() -> void:
	local_name = _chosen_name()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		status_label.text = "Could not host on port %d (error %d)" % [PORT, err]
		return
	multiplayer.multiplayer_peer = peer
	_enter_game()
	_server_add_player(1, local_name)


func _join() -> void:
	local_name = _chosen_name()
	var address := ip_input.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		status_label.text = "Could not connect (error %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting to %s ..." % address


func _enter_game() -> void:
	if world != null:
		return
	menu.queue_free()
	menu = null

	world = WorldScene.instantiate()
	world.name = "World"
	add_child(world)

	hud = HudScene.instantiate()
	add_child(hud)
	hud.bind(self, world)


# --------------------------------------------------------- connection hooks

func _on_connected_ok() -> void:
	_enter_game()
	_register_player.rpc_id(1, local_name)


func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	multiplayer.multiplayer_peer = null


func _on_server_disconnected() -> void:
	get_tree().quit()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if world != null:
		world.release_barracks(id)
	_remove_player.rpc(id)


@rpc("any_peer", "reliable")
func _register_player(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	_server_add_player(id, pname)


func _server_add_player(id: int, pname: String) -> void:
	# Tell the newcomer about everyone already here, then announce them to all.
	for existing_id in players.keys():
		var existing: Node = players[existing_id]
		_add_player.rpc_id(id, existing_id, player_names.get(existing_id, "Player"), existing.global_position)

	var spawn: Vector3 = world.claim_barracks(id)
	_add_player.rpc(id, pname, spawn)

	# Bring the newcomer up to date on world state.
	world._sync_phase.rpc_id(id, world.battle_active, world.phase_time_left)
	world._sync_boundary.rpc_id(id, world.boundary_radius)
	world._set_egg.rpc_id(id, world.egg_position)


@rpc("authority", "call_local", "reliable")
func _add_player(id: int, pname: String, pos: Vector3) -> void:
	if players.has(id) or world == null:
		return
	var player := PlayerScene.instantiate()
	player.name = str(id)
	player.peer_id = id
	player.player_name = pname
	world.add_child(player)
	player.set_display_name(pname)
	player.teleport(pos)
	players[id] = player
	player_names[id] = pname


@rpc("authority", "call_local", "reliable")
func _remove_player(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
	player_names.erase(id)


func local_player() -> Node:
	return players.get(multiplayer.get_unique_id())
