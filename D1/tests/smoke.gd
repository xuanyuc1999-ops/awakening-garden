extends SceneTree

# Drives the ordinary input handlers and CharacterBody3D through the real scene.
# No teleport, inventory injection, maturity injection or direct win call is used.
var game
var checks: Array = []
var pressed: Dictionary = {}
var failed = false
var screenshot_enabled = false

func _initialize() -> void:
	call_deferred("run")

func frame(count: int = 1) -> void:
	for i in range(count):
		# Windows releases held keys when another window gets focus.
		# Re-send only the controller's still-held movement/orbit keys.
		for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_LEFT, KEY_RIGHT]:
			if pressed.get(code, false) and not Input.is_physical_key_pressed(code):
				key(code, true)
		await physics_frame

func key(code: int, down: bool) -> void:
	if pressed.get(code, false) == down and (not down or Input.is_physical_key_pressed(code)):
		return
	pressed[code] = down
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func tap(code: int) -> void:
	key(code, true)
	await frame(2)
	key(code, false)
	await frame(3)

func release_movement() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]:
		key(code, false)

func walk_to(x: float, z: float) -> void:
	for i in range(500):
		if failed:
			return
		var delta = Vector2(x - game.player.position.x, z - game.player.position.z)
		if delta.length() < 0.24:
			release_movement()
			await frame(8)
			return
		key(KEY_D, delta.x > 0.16)
		key(KEY_A, delta.x < -0.16)
		key(KEY_S, delta.y > 0.16)
		key(KEY_W, delta.y < -0.16)
		await frame(3)
	release_movement()
	check(false, "Walk target unreachable: %s, %s; player %s" % [x, z, game.player.position])

func check(condition: bool, description: String) -> void:
	checks.append({"passed": condition, "description": description, "tick": Engine.get_physics_frames()})
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failed = true
		save_report()
		quit(1)

func event_count(name: String) -> int:
	var count = 0
	for event in game.events:
		if event.name == name:
			count += 1
	return count

func capture(name: String) -> void:
	if not screenshot_enabled:
		return
	await frame(12)
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	image.save_png("res://evidence/" + name + ".png")

func save_report() -> void:
	var file = FileAccess.open("res://evidence/" + ("visual-smoke.json" if screenshot_enabled else "smoke.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"status": "fail" if failed else "pass",
		"engine": Engine.get_version_info(),
		"physics": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"execution": "Godot simulated keyboard input through normal handlers and real physics; no OS input or human playtest",
		"rendered": screenshot_enabled,
		"diagnostics": {"player": str(game.player.position), "velocity": str(game.player.velocity), "camera_yaw": game.camera_yaw, "active": game.active},
		"checks": checks,
		"events": game.events,
		"final_state": {"bridge": game.bridge_open, "gate": game.gate_open, "won": game.won, "seeds": game.seeds, "materials": game.materials, "reset_count": game.reset_count}
	}, "\t"))
	file.close()

func run() -> void:
	screenshot_enabled = DisplayServer.get_name() != "headless"
	change_scene_to_file("res://main.tscn")
	await process_frame
	await frame(3)
	game = current_scene
	game.automated = true
	check(game != null and game.menu_mode == "start" and not game.active, "Normal startup opens the introduction")
	var viewport_rect = root.get_visible_rect()
	check(viewport_rect.encloses(game.hud.primary.get_global_rect()), "Start button is fully inside the viewport")
	check(viewport_rect.encloses(game.hud.stock.get_global_rect()), "Inventory is fully inside the viewport")
	check(viewport_rect.encloses(game.hud.map.get_global_rect()), "Map is fully inside the viewport")
	await capture("00-introduction")
	await tap(KEY_ENTER)
	check(game.active, "Enter starts the game")
	key(KEY_LEFT, true)
	await frame(15)
	key(KEY_LEFT, false)
	check(game.camera_yaw > 0.2, "Keyboard orbit rotates the real camera")
	key(KEY_RIGHT, true)
	await frame(15)
	key(KEY_RIGHT, false)
	await frame(2)
	check(absf(game.camera_yaw) < 0.01, "Opposite orbit restores the forward heading")
	await tap(KEY_E)
	check(game.materials == 0 and event_count("action.denied") >= 1, "Interaction out of range changes no resources")
	# Real fall and recovery, before any mechanism has opened.
	await walk_to(4, 2)
	var before_recovery = event_count("player.recovered")
	key(KEY_W, true)
	await frame(110)
	key(KEY_W, false)
	await frame(8)
	check(event_count("player.recovered") > before_recovery and game.seeds == [3, 0], "Falling into the trench returns the player without resource loss")
	await walk_to(0, 4.7)
	check(game.target == game.get_node("Plots/VineLock"), "The correct bridge plot is reachable and highlighted")
	await tap(KEY_E)
	var vine = game.get_node("Plots/VineLock")
	check(vine.stage == 1, "Till hard ground")
	await tap(KEY_2)
	await tap(KEY_E)
	check(vine.stage == 1 and game.seeds[1] == 0, "Unavailable seeds cannot be planted")
	await tap(KEY_1)
	await tap(KEY_E)
	check(vine.stage == 2 and game.seeds[0] == 2, "Sowing consumes exactly one seed")
	await tap(KEY_T)
	check(vine.stage == 2 and not game.bridge_open, "Unwatered seeds do not grow when time advances")
	await tap(KEY_E)
	check(vine.stage == 3, "Watering starts growth")
	await tap(KEY_E)
	check(game.materials == 0 and vine.stage == 3, "Immature plants cannot be harvested")
	await tap(KEY_ESCAPE)
	var paused_hour = game.hours
	var paused_growth = vine.growth
	await tap(KEY_T)
	await frame(30)
	check(game.hours == paused_hour and vine.growth == paused_growth, "Pause blocks time skip and freezes crop growth")
	await tap(KEY_ESCAPE)
	check(game.active, "Escape resumes")
	await tap(KEY_T)
	await capture("01-growing-vine")
	await tap(KEY_T)
	await tap(KEY_T)
	await frame(8)
	check(vine.stage == 4 and game.bridge_open and not game.bridge_collision.disabled, "Mature vine opens a real walkable bridge")
	await capture("02-bridge")
	await tap(KEY_E)
	check(game.materials == 1 and game.seeds[0] == 4 and vine.stage == 1, "Harvest returns two seeds and one material")
	check(game.bridge_open, "Bridge stays open after harvesting its plant")
	await tap(KEY_E)
	check(game.materials == 1, "A second interaction cannot double-award a harvest")
	await tap(KEY_F)
	check(vine.stage == 1 and game.seeds[0] == 4, "Uprooting refunds the planted seed")
	await walk_to(0, -8)
	check(game.player.position.y > -0.2 and game.checkpoint.z < 0, "Walk across the new bridge; checkpoint advances")
	await walk_to(3, -8)
	await tap(KEY_E)
	check(game.seed_cache_taken and game.seeds[1] == 2, "Collect the new seed species through interaction")
	await tap(KEY_E)
	check(game.seeds[1] == 2, "Seed cache cannot be collected twice")
	await walk_to(0, -14.8)
	key(KEY_W, true)
	await frame(100)
	key(KEY_W, false)
	check(game.player.position.z > -19.2 and not game.gate_open, "Closed rubble physically blocks the third area")
	await walk_to(0, -14.8)
	var roots = game.get_node("Plots/RootLock")
	check(game.target == roots, "Root mechanism plot is reachable before the barrier")
	await tap(KEY_E)
	await tap(KEY_1)
	await tap(KEY_E)
	await tap(KEY_E)
	for i in range(3):
		await tap(KEY_T)
	check(roots.stage == 4 and not game.gate_open, "Wrong mature crop does not open the rock mechanism")
	await tap(KEY_F)
	check(roots.stage == 1 and game.seeds[0] == 4, "Wrong planting can be recovered without losing seeds")
	await tap(KEY_2)
	await tap(KEY_E)
	await tap(KEY_E)
	for i in range(3):
		await tap(KEY_T)
	await frame(85)
	check(game.gate_open and game.gate_collision.disabled, "Mature deep-root plant removes the rubble collision")
	await capture("03-root-gate")
	# Test insufficient material without harvesting the second plant yet.
	await walk_to(0, -28.7)
	check(game.target == game.altar, "Walk through cleared gate to the source stone")
	await tap(KEY_E)
	check(not game.won and game.materials == 1, "Awakening refuses insufficient materials")
	await walk_to(0, -18.5)
	await tap(KEY_E)
	check(game.materials == 2 and game.seeds[1] == 3, "Deep-root harvest gives the second material")
	await walk_to(0, -28.7)
	await tap(KEY_E)
	check(game.won and game.materials == 0 and game.menu_mode == "win", "Complete the full loop and awaken the garden")
	check(event_count("bridge.opened") == 1 and event_count("gate.opened") == 1 and event_count("garden.awakened") == 1, "Mechanism unlocks and victory are each awarded once")
	await capture("04-awakened")
	await tap(KEY_ENTER)
	await tap(KEY_E)
	check(game.materials == 0 and event_count("garden.awakened") == 1, "Post-victory interaction cannot charge or award again")
	await walk_to(-4, -27.9)
	await tap(KEY_E)
	check(game.get_node("Plots/FinalA").stage == 1, "Newly unlocked final-area plots can be cultivated")
	await tap(KEY_H)
	check(game.player.position.z < -23 and game.materials == 0, "Manual return uses the final checkpoint and preserves progress")
	await tap(KEY_R)
	await tap(KEY_ENTER)
	await frame(5)
	check(not game.bridge_open and not game.gate_open and not game.won, "Restart resets both mechanisms and victory")
	check(game.seeds == [3, 0] and game.materials == 0 and not game.seed_cache_taken, "Restart resets inventories and seed pickup")
	check(game.bridge_collision.disabled and not game.gate_collision.disabled, "Restart restores bridge and gate collision states")
	var all_hard = true
	for plot in game.get_node("Plots").get_children():
		all_hard = all_hard and plot.stage == 0
	check(all_hard and game.player.position.distance_to(game.SPAWN) < 0.2, "Restart restores all plots and the player")
	# Reset while a plant is actively growing: no deferred unlock may survive.
	await walk_to(0, 4.7)
	for i in range(3):
		await tap(KEY_E)
	await tap(KEY_R)
	await tap(KEY_ENTER)
	for i in range(4):
		await tap(KEY_T)
	check(not game.bridge_open and vine.stage == 0 and game.seeds == [3, 0], "Restart during growth leaves no late maturity or resource residue")
	save_report()
	print("GARDEN_SMOKE_PASS: %d checks" % checks.size())
	quit(0)
