extends SceneTree

# Drives the ordinary input handlers and CharacterBody3D through the real scene.
# No teleport, inventory injection, maturity injection or direct win call is used.
var game
var farmer_source_sha256 = ""
var farmer_closeups: Array = []
var evidence_output = ""
var attempt_id = ""
var binding_digest = ""
var camera_probe_report: Array = []
var checks: Array = []
var pressed: Dictionary = {}
var failed = false
var screenshot_enabled = false

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	farmer_source_sha256 = args[args.find("--farmer-source-sha256") + 1]
	evidence_output = args[args.find("--output") + 1]
	attempt_id = args[args.find("--attempt-id") + 1]
	binding_digest = args[args.find("--binding-digest") + 1]
	DirAccess.make_dir_recursive_absolute(evidence_output)
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
	RenderingServer.force_draw(false)
	var image = root.get_texture().get_image()
	image.save_png(evidence_output + "/" + name + ".png")
	if name in ["02-bridge", "03-root-gate", "04-awakened"]:
		game.hud.visible = false
		await frame(2)
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(evidence_output + "/" + name + "-clean.png")
		game.hud.visible = true
	if name == "02b-bridge-center":
		await inspect_camera_views()

func save_report() -> void:
	var file = FileAccess.open(evidence_output + "/" + ("visual-smoke.json" if screenshot_enabled else "smoke.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"status": "fail" if failed else "pass",
		"engine": Engine.get_version_info(),
		"physics": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"execution": "Godot simulated keyboard input through normal handlers and real physics; no OS input or human playtest",
		"rendered": screenshot_enabled,
		"farmer_report": farmer_report(),
		"refinement": {"ground": game.get_node("_GroundDetail").get_report(), "plants": game.get_node("_PlantDetail").get_report(), "environment": game.get_node("_SceneDetail").get_report()},
		"farmer_closeups": farmer_closeups,
		"attempt_id": attempt_id,
		"binding_digest": binding_digest,
		"scene": "res://art/refinement-r3/D1/play.tscn",
		"art_report": game.get_node("_GreyboxArtLayer").get_report(),
		"look_report": game.get_node("_GardenLook").get_report(),
		"camera_probe_report": camera_probe_report,
		"diagnostics": {"player": str(game.player.position), "velocity": str(game.player.velocity), "camera_yaw": game.camera_yaw, "active": game.active},
		"checks": checks,
		"events": game.events,
		"final_state": {"bridge": game.bridge_open, "gate": game.gate_open, "won": game.won, "seeds": game.seeds, "materials": game.materials, "reset_count": game.reset_count}
	}, "\t"))
	file.close()

func run() -> void:
	screenshot_enabled = DisplayServer.get_name() != "headless"
	change_scene_to_file("res://art/refinement-r3/D1/play.tscn")
	await process_frame
	await frame(3)
	game = current_scene
	game.automated = true
	await frame(3)
	verify_farmer()
	verify_refinement()
	if failed: return
	await frame(3)
	var art = game.get_node("_GreyboxArtLayer")
	check(art.assembled and art.assembly_errors.is_empty(), "All 14 actual models assemble successfully")
	if failed: return
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
	await walk_to(0, -3)
	check(game.player.is_on_floor(), "The generated bridge center supports ordinary walking")
	await capture("02b-bridge-center")
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
	check(game.get_node("_GreyboxArtLayer").get_report().collider_inventory_unchanged, "Production art preserves collider identities")
	check(farmer_report().get("played_clips", []).size() >= 2, "Farmer actually switches idle and walk clips")
	check(farmer_report().get("collider_unchanged", false) == true, "Farmer collider remains unchanged after gameplay and restart")
	if failed: return
	if screenshot_enabled and not OS.get_cmdline_user_args().has("--no-closeups"):
		await capture_farmer_views()
		if failed: return
	save_report()
	print("GARDEN_SMOKE_PASS: %d checks" % checks.size())
	quit(0)


func inspect_camera_views() -> void:
	var yaw = game.camera_yaw
	var pitch = game.camera_pitch
	var distance = game.camera_distance
	var was_active = game.active
	game.active = false
	game.hud.visible = false
	var combinations = [
		["near", 0.0, -0.67, 6.0],
		["far", 0.0, -0.67, 15.0],
		["return", PI, -0.67, 10.0],
		["side", PI * 0.5, -0.67, 10.0],
	]
	for c in combinations:
		game.camera_yaw = c[1]
		game.camera_pitch = c[2]
		game.camera_distance = c[3]
		await frame(15)
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(evidence_output + "/camera-" + c[0] + ".png")
		var camera = game.get_node("CameraRig/SpringArm3D/Camera3D")
		var collision = game.get_node("CameraRig/SpringArm3D").get_hit_length()
		camera_probe_report.append({"view":c[0],"position":str(camera.global_position),
			"spring_hit_length":collision,"finite":camera.global_position.is_finite(),
			"scope":"Camera-state visual probe during normal walkthrough; not OS mouse testing"})
	game.camera_yaw = yaw
	game.camera_pitch = pitch
	game.camera_distance = distance
	game.hud.visible = true
	game.active = was_active
	await frame(12)


func verify_refinement() -> void:
	var ground = game.get_node("_GroundDetail").get_report()
	var plants = game.get_node("_PlantDetail").get_report()
	var environment = game.get_node("_SceneDetail").get_report()
	check(ground.get("ready", false) and ground.get("errors", []).is_empty(), "Refined ground assembled")
	check(plants.get("ready", false) and plants.get("errors", []).is_empty(), "Refined plants assembled")
	check(environment.get("ready", false) and environment.get("errors", []).is_empty(), "Refined environment assembled")
	check(environment.get("collider_inventory_unchanged", false), "Refinement preserves collider identities")
	check(ground.get("max_tread_y", 1.0) <= 0.0251, "Ground detail respects the tread limit")

func farmer_report() -> Dictionary:
	if not is_instance_valid(game):
		return {}
	var visual = game.get_node_or_null("_FarmerVisual")
	if visual == null or not visual.has_method("get_report"):
		return {}
	var report = visual.get_report()
	return report if report is Dictionary else {}

func farmer_count(value: Variant, minimum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and float(value) >= minimum and floor(float(value)) == float(value)

func verify_farmer() -> void:
	var visual = game.get_node_or_null("_FarmerVisual")
	check(visual != null and visual.has_method("get_report"), "Farmer visual exposes get_report")
	if failed: return
	# The adapter must derive these counts from its live Skeleton3D/AnimationPlayer.
	var report = farmer_report()
	check(report.get("ready", false) == true, "Farmer visual is ready")
	if failed: return
	var skeleton_ok = farmer_count(report.get("skeleton_bones", 0), 1)
	if report.has("skeleton_count"):
		skeleton_ok = skeleton_ok and farmer_count(report.skeleton_count, 1)
	check(skeleton_ok, "Farmer contains a skeleton with bones")
	if failed: return
	check(farmer_count(report.get("animation_count", 0), 2), "Farmer contains at least two animation clips")
	if failed: return
	check(report.get("source_sha256", "") == farmer_source_sha256, "Farmer source SHA256 matches the supplied asset")
	if failed: return
	check(report.get("collider_unchanged", false) == true, "Farmer preserves the player collider")
	if failed: return
	var height = report.get("bounds_height", 0.0)
	var height_ok = typeof(height) == TYPE_FLOAT or typeof(height) == TYPE_INT
	if height_ok:
		height_ok = is_finite(float(height)) and float(height) > 0.0
	check(height_ok, "Farmer bounds height is finite and positive")

func capture_farmer_views() -> void:
	# Runs AFTER all gameplay checks. Only the inspection camera/HUD/activity change.
	# Front is Player/Body local -Z, matching the existing movement controller.
	var original_camera = root.get_camera_3d()
	var was_active = game.active
	var hud_visible = game.hud.visible
	release_movement()
	game.active = false
	game.hud.visible = false
	var height = float(farmer_report().get("bounds_height", 1.8))
	var body = game.player.get_node_or_null("Body")
	var facing_basis = game.player.global_basis if body == null else body.global_basis
	var forward = -facing_basis.z.normalized()
	var right = facing_basis.x.normalized()
	var center = game.player.global_position + Vector3.UP * height * 0.5
	var camera = Camera3D.new()
	game.add_child(camera)
	camera.fov = 38.0
	camera.near = 0.02
	camera.far = maxf(100.0, height * 10.0)
	camera.make_current()
	var distance = maxf(0.5, height * 1.85)
	for view in [["front", forward], ["back", -forward], ["side", right]]:
		camera.global_position = center + view[1] * distance + Vector3.UP * height * 0.08
		camera.look_at(center, Vector3.UP)
		await frame(4)
		RenderingServer.force_draw(false)
		var image = root.get_texture().get_image()
		var error = image.save_png(evidence_output + "/farmer-" + view[0] + ".png")
		farmer_closeups.append({"view": view[0], "save_error": error,
			"camera_position": str(camera.global_position), "target": str(center),
			"orientation": "Player/Body local -Z front; visual adapter must align with this",
			"scope": "Post-gameplay visual inspection; no animation-quality or OS-input certification"})
		if error != OK:
			failed = true
			push_error("Farmer close-up PNG write failed: " + view[0])
	if is_instance_valid(original_camera):
		original_camera.make_current()
	camera.queue_free()
	game.hud.visible = hud_visible
	game.active = was_active
	if failed:
		save_report()
		quit(1)
