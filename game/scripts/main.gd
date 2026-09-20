extends Node3D

## Bootstrap: sign-in flow, ENet connection, and player spawn replication.

const PORT := 8910
const MAX_PLAYERS := 16

const WorldScene := preload("res://scenes/world.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const HudScene := preload("res://scenes/hud.tscn")

var world: Node3D
var hud: CanvasLayer
var menu: CanvasLayer
var menu_box: VBoxContainer
var status_label: Label

var local_name := "Player"
var players: Dictionary = {}
var player_names: Dictionary = {}

var _phone := ""
var _expected_code := ""
var _server_address := "127.0.0.1"


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	_build_environment()
	_build_menu()

	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		_host()
	elif "--client" in OS.get_cmdline_user_args():
		_join()


func _build_environment() -> void:
	GameEnvironment.build(self)


# ------------------------------------------------------------------ sign-in

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

	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 10)
	center.add_child(menu_box)

	_show_sign_in()


func _clear_menu() -> void:
	for child in menu_box.get_children():
		child.queue_free()


func _heading(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	return label


func _field(placeholder: String, initial := "") -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = initial
	edit.custom_minimum_size = Vector2(340, 40)
	return edit


func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(340, 46)
	button.pressed.connect(handler)
	return button


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _add_status() -> void:
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size = Vector2(340, 26)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_box.add_child(status_label)


func _show_sign_in() -> void:
	_clear_menu()
	menu_box.add_child(_heading("GOLDEN EGG", 48))
	menu_box.add_child(_heading("Sign in to play", 16))
	menu_box.add_child(_spacer(18))

	var name_field := _field("Your name", local_name if local_name != "Player" else "")
	menu_box.add_child(name_field)

	var phone_field := _field("Phone number", _phone)
	menu_box.add_child(phone_field)

	menu_box.add_child(_button("Send verification code", func() -> void:
		_request_code(name_field.text, phone_field.text)))

	_add_status()


func _request_code(entered_name: String, entered_phone: String) -> void:
	var clean_name := entered_name.strip_edges()
	var digits := ""
	for character in entered_phone:
		if character >= "0" and character <= "9":
			digits += character

	if clean_name.length() < 2:
		status_label.text = "Enter a name of at least 2 characters."
		return
	if digits.length() < 8 or digits.length() > 15:
		status_label.text = "Enter a valid phone number (8-15 digits)."
		return

	local_name = clean_name
	_phone = digits
	_expected_code = "%06d" % (randi() % 1000000)
	_show_verify()


func _show_verify() -> void:
	_clear_menu()
	menu_box.add_child(_heading("Enter your code", 30))
	menu_box.add_child(_heading("Sent to " + _masked_phone(), 15))
	menu_box.add_child(_spacer(12))

	var code_field := _field("6-digit code")
	code_field.max_length = 6
	menu_box.add_child(code_field)

	menu_box.add_child(_button("Verify", func() -> void:
		_verify_code(code_field.text)))
	menu_box.add_child(_button("Use a different number", func() -> void:
		_show_sign_in()))

	# No SMS provider is wired up yet, so the code is shown here instead.
	var dev_note := Label.new()
	dev_note.text = "Development build — no SMS service connected.\nYour code is %s" % _expected_code
	dev_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev_note.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	menu_box.add_child(dev_note)

	_add_status()


func _masked_phone() -> String:
	if _phone.length() <= 4:
		return _phone
	return "*".repeat(_phone.length() - 4) + _phone.substr(_phone.length() - 4)


func _verify_code(entered: String) -> void:
	if entered.strip_edges() != _expected_code:
		status_label.text = "That code doesn't match. Try again."
		return
	_show_play()


func _show_play() -> void:
	_clear_menu()
	menu_box.add_child(_heading("Welcome, " + local_name, 30))
	menu_box.add_child(_heading("Find the egg. Survive the battle window.", 15))
	menu_box.add_child(_spacer(18))

	var address_field := _field("Server address", _server_address)
	menu_box.add_child(address_field)

	menu_box.add_child(_button("Play", func() -> void:
		_server_address = address_field.text.strip_edges()
		_join()))

	menu_box.add_child(_spacer(10))
	menu_box.add_child(_button("Run a local server (development)", _host))

	_add_status()

	var help := Label.new()
	help.text = "WASD move · Shift sprint · Space jump · Mouse look · Click shoot (battle only) · Esc release cursor"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_box.add_child(help)


# --------------------------------------------------------------- networking

func _host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		if status_label != null:
			status_label.text = "Could not host on port %d (error %d)" % [PORT, err]
		return
	multiplayer.multiplayer_peer = peer
	_enter_game()
	_server_add_player(1, local_name)


func _join() -> void:
	var address := _server_address if _server_address != "" else "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		if status_label != null:
			status_label.text = "Could not connect (error %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	if status_label != null:
		status_label.text = "Connecting to %s ..." % address


func _enter_game() -> void:
	if world != null:
		return
	menu.queue_free()
	menu = null
	menu_box = null
	status_label = null

	world = WorldScene.instantiate()
	world.name = "World"
	add_child(world)

	hud = HudScene.instantiate()
	add_child(hud)
	hud.bind(self, world)


func _on_connected_ok() -> void:
	_enter_game()
	_register_player.rpc_id(1, local_name)


func _on_connection_failed() -> void:
	if status_label != null:
		status_label.text = "Connection failed. Is the server running?"
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
