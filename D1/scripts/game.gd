extends Node3D

const Plot = preload("res://scripts/plot.gd")
const HUD = preload("res://scripts/hud.gd")
const REAL_SECONDS_PER_HOUR = 8.0
const INTERACTION_RANGE = 2.6
const SPAWN = Vector3(0, 0.08, 12)

var active = false
var menu_mode = "start"
var won = false
var bridge_open = false
var gate_open = false
var seed_cache_taken = false
var selected_crop = 0
var seeds = [3, 0]
var materials = 0
var hours = 8.0
var checkpoint = SPAWN
var target
var toast = ""
var toast_time = 0.0
var events: Array = []
var tweens: Array = []
var reset_count = 0
var camera_yaw = 0.0
var camera_pitch = -0.67
var camera_distance = 10.0
var hud
var automated = false

@onready var player = $Player
@onready var pivot = $CameraRig
@onready var arm = $CameraRig/SpringArm3D
@onready var bridge = $Mechanisms/Bridge
@onready var bridge_collision = $Mechanisms/Bridge/Body/CollisionShape3D
@onready var gate = $Mechanisms/Gate
@onready var gate_collision = $Mechanisms/Gate/Body/CollisionShape3D
@onready var seed_cache = $Pickups/RootSeeds
@onready var altar = $Mechanisms/Altar
@onready var sun = $Sun
@onready var environment = $WorldEnvironment
@onready var revived = $Revival

func _ready() -> void:
	automated = "--autoplay" in OS.get_cmdline_user_args()
	_setup_input()
	player.game = self
	for plot in $Plots.get_children():
		plot.game = self
		plot.refresh()
	arm.add_excluded_object(player.get_rid())
	hud = CanvasLayer.new()
	hud.set_script(HUD)
	hud.name = "Interface"
	add_child(hud)
	pivot.position = player.position + Vector3.UP * 1.1
	bridge.visible = false
	bridge_collision.disabled = true
	revived.visible = false
	hud.show_menu("start")
	update_camera(1.0)
	update_light()
	record("session.ready", {"engine": Engine.get_version_info().string, "physics": ProjectSettings.get_setting("physics/3d/physics_engine")})

func _setup_input() -> void:
	var keys = {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "interact": KEY_E, "uproot": KEY_F, "wait_hour": KEY_T,
		"seed_vine": KEY_1, "seed_root": KEY_2, "home": KEY_H,
		"restart": KEY_R, "orbit_left": KEY_LEFT, "orbit_right": KEY_RIGHT,
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var input = InputEventKey.new()
		input.physical_keycode = keys[action]
		InputMap.action_add_event(action, input)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_ESCAPE:
			if menu_mode == "start":
				return
			if not active:
				menu_secondary() if menu_mode == "restart" else resume_game()
			else:
				pause_game("pause")
			get_viewport().set_input_as_handled()
			return
		if not active:
			if key == KEY_ENTER or key == KEY_KP_ENTER:
				menu_primary()
				get_viewport().set_input_as_handled()
			return
		record("input.action", {"key": key})
		match key:
			KEY_E:
				interact()
			KEY_F:
				if target != null and target.is_in_group("plots"):
					target.uproot()
			KEY_1:
				selected_crop = 0
				message("已选择藤蔓种子。")
			KEY_2:
				selected_crop = 1
				message("已选择深根种子。" if seed_cache_taken else "深根种子在沟壑另一侧，先让藤蔓搭桥。")
			KEY_T:
				advance_time(1.0)
				message("时间推进一小时。")
			KEY_H:
				recover_player()
			KEY_R:
				pause_game("restart")
	elif event is InputEventMouseButton and active:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(6.0, camera_distance - 0.7)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(15.0, camera_distance + 0.7)
	elif event is InputEventMouseMotion and active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * 0.004
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.003, -1.1, -0.28)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and active and not automated:
		pause_game("pause")

func _process(delta: float) -> void:
	if hud == null:
		return
	if active:
		advance_time(delta / REAL_SECONDS_PER_HOUR)
		camera_yaw += (Input.get_action_strength("orbit_left") - Input.get_action_strength("orbit_right")) * delta * 1.4
		toast_time = maxf(0, toast_time - delta)
		update_target()
		if bridge_open and player.position.z < -8.0 and player.position.y > -0.1:
			checkpoint = Vector3(0, 0.08, -10)
		if gate_open and player.position.z < -23.0 and player.position.y > -0.1:
			checkpoint = Vector3(0, 0.08, -25)
	update_camera(delta)
	hud.update_hud()

func update_camera(delta: float) -> void:
	pivot.position = pivot.position.lerp(player.position + Vector3.UP * 1.1, minf(delta * 10.0, 1.0))
	pivot.rotation = Vector3(camera_pitch, camera_yaw, 0)
	arm.spring_length = camera_distance

func update_light() -> void:
	var daylight = (sin((fmod(hours, 24.0) - 6.0) / 24.0 * TAU) + 1.0) * 0.5
	sun.light_energy = lerpf(0.35, 1.1, daylight)
	sun.rotation_degrees = Vector3(-38.0 - daylight * 22.0, -28.0 + fmod(hours, 24.0) * 3.0, 0)
	environment.environment.ambient_light_energy = lerpf(0.55, 0.8, daylight)
	environment.environment.background_color = Color(0.18, 0.20, 0.24).lerp(Color(0.52, 0.56, 0.58), daylight)

func advance_time(amount: float) -> void:
	hours += amount
	for plot in $Plots.get_children():
		plot.advance(amount)
	update_light()

func update_target() -> void:
	var best
	var distance = INTERACTION_RANGE
	var candidates = $Plots.get_children()
	if bridge_open and not seed_cache_taken:
		candidates.append(seed_cache)
	if gate_open:
		candidates.append(altar)
	for item in candidates:
		if item.is_in_group("plots") and not item.available():
			continue
		var to = item.global_position - player.global_position
		var horizontal = Vector2(to.x, to.z).length()
		if horizontal > distance or absf(to.y) > 2.0:
			continue
		var from = player.global_position + Vector3.UP * 1.0
		var end = item.global_position + Vector3.UP * 0.8
		var query = PhysicsRayQueryParameters3D.create(from, end, 1, [player.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		distance = horizontal
		best = item
	if target != best:
		if is_instance_valid(target) and target.is_in_group("plots"):
			target.set_selected(false)
		target = best
		if target != null and target.is_in_group("plots"):
			target.set_selected(true)

func interact() -> bool:
	# Re-evaluate reach/occlusion on the input frame, never trust a stale highlight.
	update_target()
	if target == null:
		message("靠近地块、种子箱或源石再按 E。")
		record("action.denied", {"reason": "out_of_reach"})
		return false
	if target.is_in_group("plots"):
		return target.interact()
	if target == seed_cache:
		if seed_cache_taken:
			return false
		seed_cache_taken = true
		seeds[1] += 2
		selected_crop = 1
		seed_cache.visible = false
		record("seeds.collected", {"crop": 1, "count": 2})
		message("获得深根种子 ×2。去碎石前带标记的地块种下它。")
		target = null
		return true
	if target == altar:
		if won:
			return false
		if materials < 2:
			message("需要 2 份作物素材。回到成熟地块收获即可。")
			record("action.denied", {"reason": "materials", "current": materials})
			return false
		materials -= 2
		won = true
		revived.visible = true
		$Mechanisms/Altar/Light.light_energy = 3.5
		record("garden.awakened", {"materials_remaining": materials})
		pause_game("win")
		return true
	return false

func on_crop_matured(plot) -> void:
	if plot.required_crop == -1:
		message("作物成熟了，可以收获。")
		return
	if plot.crop != plot.required_crop:
		message("作物成熟了，但特性与这里的机关不匹配。可收获或按 F 换种。")
		record("puzzle.wrong_crop", {"plot": plot.plot_id, "crop": plot.crop})
		return
	if plot.required_crop == 0 and not bridge_open:
		bridge_open = true
		bridge.visible = true
		bridge_collision.set_deferred("disabled", false)
		$World/BridgeLabel.text = "藤蔓桥已连接\n可以过桥探索新地块"
		for plank in $Mechanisms/Bridge/Planks.get_children():
			plank.scale.y = 0.08
			var tween = create_tween()
			tween.tween_property(plank, "scale:y", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
			tweens.append(tween)
		record("bridge.opened", {"plot": plot.plot_id})
		message("藤蔓连起了断路！收获后过桥，寻找新的种子。")
	elif plot.required_crop == 1 and bridge_open and not gate_open:
		gate_open = true
		gate_collision.set_deferred("disabled", true)
		$Mechanisms/Gate/GateLabel.text = "石径已贯通\n前往源石，唤醒园地"
		var i = 0
		for stone in $Mechanisms/Gate/Stones.get_children():
			var tween = create_tween().set_parallel(true)
			var offset = Vector3(-4.0 if i % 2 == 0 else 4.0, -0.3, 0.0)
			tween.tween_property(stone, "position", stone.position + offset, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(stone, "rotation:z", (-0.7 if i % 2 == 0 else 0.7), 1.2)
			tweens.append(tween)
			i += 1
		record("gate.opened", {"plot": plot.plot_id})
		message("深根推开了碎石！带上两份收获素材，去尽头唤醒源石。")
	for item in $Plots.get_children():
		item.refresh()

func recover_player() -> void:
	player.position = checkpoint
	player.velocity = Vector3.ZERO
	pivot.position = player.position + Vector3.UP * 1.1
	message("已返回安全位置，种植和资源进度保留。")
	record("player.recovered", {"position": [checkpoint.x, checkpoint.y, checkpoint.z]})

func pause_game(mode: String) -> void:
	active = false
	menu_mode = mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for tween in tweens:
		if tween.is_valid():
			tween.set_speed_scale(0)
	hud.show_menu(mode)
	record("menu.opened", {"mode": mode})

func resume_game() -> void:
	active = true
	menu_mode = ""
	hud.menu.visible = false
	for tween in tweens:
		if tween.is_valid():
			tween.set_speed_scale(1)
	record("session.resumed")

func menu_primary() -> void:
	if menu_mode == "restart":
		reset_game()
	else:
		var starting = menu_mode == "start"
		resume_game()
		if starting:
			message("先到沟边有「藤蔓 → 沟壑」标记的地块，按 E 翻土。")
			record("session.started")

func menu_secondary() -> void:
	if menu_mode == "restart":
		resume_game()
	else:
		pause_game("restart")

func reset_game() -> void:
	for tween in tweens:
		if tween.is_valid():
			tween.kill()
	tweens.clear()
	bridge_open = false
	gate_open = false
	won = false
	seed_cache_taken = false
	selected_crop = 0
	seeds = [3, 0]
	materials = 0
	hours = 8.0
	checkpoint = SPAWN
	player.position = SPAWN
	player.velocity = Vector3.ZERO
	camera_yaw = 0
	camera_pitch = -0.67
	camera_distance = 10.0
	pivot.position = SPAWN + Vector3.UP * 1.1
	if target != null and target.is_in_group("plots"):
		target.set_selected(false)
	target = null
	for plot in $Plots.get_children():
		plot.reset_plot()
	bridge.visible = false
	bridge_collision.set_deferred("disabled", true)
	gate_collision.set_deferred("disabled", false)
	$World/BridgeLabel.text = "断路\n成熟的藤蔓可以连接两岸"
	$Mechanisms/Gate/GateLabel.text = "碎石封路\n深根在石前成熟时，通路打开"
	for stone in $Mechanisms/Gate/Stones.get_children():
		stone.position = stone.get_meta("initial_position")
		stone.rotation = stone.get_meta("initial_rotation")
	seed_cache.visible = true
	revived.visible = false
	$Mechanisms/Altar/Light.light_energy = 0.0
	reset_count += 1
	resume_game()
	record("session.reset", {"count": reset_count})
	message("园地已恢复初始状态。")
	update_light()

func zone_name() -> String:
	if player.position.z < -20:
		return "03 源地"
	if player.position.z < -6:
		return "02 石径"
	return "01 起始园地"

func message(text: String) -> void:
	toast = text
	toast_time = 6.0

func record(event: String, detail: Dictionary = {}) -> void:
	events.append({"name": event, "tick": Engine.get_physics_frames(), "hour": hours, "detail": detail})
