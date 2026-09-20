extends CanvasLayer

## On-screen state: coins, health, current phase, egg direction, kill feed.

var main: Node3D
var world: Node3D

var phase_label: Label
var timer_label: Label
var coins_label: Label
var health_bar: ProgressBar
var boundary_label: Label
var compass_label: Label
var feed_box: VBoxContainer
var crosshair: ColorRect


func _ready() -> void:
	add_to_group("hud")
	_build()


func bind(main_node: Node3D, world_node: Node3D) -> void:
	main = main_node
	world = world_node


func _build() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-190, 12)
	top.custom_minimum_size = Vector2(380, 0)
	add_child(top)

	var top_box := VBoxContainer.new()
	top.add_child(top_box)

	phase_label = Label.new()
	phase_label.text = "HUNT"
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 24)
	top_box.add_child(phase_label)

	timer_label = Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_box.add_child(timer_label)

	compass_label = Label.new()
	compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_box.add_child(compass_label)

	# Bottom-left status block
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.position = Vector2(20, -110)
	bottom.custom_minimum_size = Vector2(260, 0)
	add_child(bottom)

	coins_label = Label.new()
	coins_label.add_theme_font_size_override("font_size", 28)
	bottom.add_child(coins_label)

	health_bar = ProgressBar.new()
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	health_bar.custom_minimum_size = Vector2(240, 20)
	bottom.add_child(health_bar)

	boundary_label = Label.new()
	bottom.add_child(boundary_label)

	# Kill feed, bottom-right
	feed_box = VBoxContainer.new()
	feed_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	feed_box.position = Vector2(-420, -140)
	feed_box.custom_minimum_size = Vector2(400, 0)
	feed_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(feed_box)

	crosshair = ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.75)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.custom_minimum_size = Vector2(4, 4)
	crosshair.size = Vector2(4, 4)
	crosshair.position = Vector2(-2, -2)
	add_child(crosshair)


func push_feed(message: String) -> void:
	if feed_box == null:
		return
	var line := Label.new()
	line.text = message
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feed_box.add_child(line)
	if feed_box.get_child_count() > 5:
		feed_box.get_child(0).queue_free()
	var timer := get_tree().create_timer(9.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(line):
			line.queue_free())


func _process(_delta: float) -> void:
	if world == null or main == null:
		return

	if world.battle_active:
		phase_label.text = "BATTLE WINDOW"
		phase_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	else:
		phase_label.text = "HUNT"
		phase_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.7))

	timer_label.text = "%s for %ds" % ["PvP live" if world.battle_active else "PvP disabled", int(maxf(world.phase_time_left, 0.0))]

	var player: Node = main.local_player()
	if player == null:
		return

	coins_label.text = "%d coins" % player.coins
	health_bar.value = clampf(player.health, 0.0, 100.0)

	var flat := Vector3(player.global_position.x, 0.0, player.global_position.z)
	var dist_from_centre := flat.length()
	if dist_from_centre > world.boundary_radius:
		boundary_label.text = "OUTSIDE THE BOUNDARY — GET BACK IN"
		boundary_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	else:
		boundary_label.text = "Boundary %dm away" % int(world.boundary_radius - dist_from_centre)
		boundary_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.82))

	# Point the player at the egg — the hunt should be a race, not a random walk.
	var to_egg := Vector3(world.egg_position.x, 0.0, world.egg_position.z) - flat
	var distance := to_egg.length()
	if distance < 0.1:
		compass_label.text = ""
		return
	var facing: Vector3 = -player.global_transform.basis.z
	var angle := atan2(to_egg.x, to_egg.z) - atan2(facing.x, facing.z)
	compass_label.text = "%s  Golden egg %dm" % [_arrow_for(wrapf(angle, -PI, PI)), int(distance)]


func _arrow_for(angle: float) -> String:
	var a := rad_to_deg(angle)
	if absf(a) < 25.0:
		return "^ ahead"
	elif absf(a) > 155.0:
		return "v behind"
	elif a > 0.0:
		return "> right"
	return "< left"
