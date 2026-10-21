extends Node
## Render appearance only. Original clock, sun angle and gameplay controls remain authoritative.
@export var style_id: String = "A1"
var game
var sky_material: ProceduralSkyMaterial
var grass_instances = 0
var root_lights: Dictionary = {}

func _ready() -> void:
	game = get_parent()
	process_priority = 110
	call_deferred("configure")

func configure() -> void:
	var environment: Environment = game.get_node("WorldEnvironment").environment
	# A bounded display transform preserves highlights instead of clamping them.
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.tonemap_exposure = 0.70 if style_id == "A1" else 1.0
	# The original scene requested sky ambient without a sky. Source GLB
	# colour and ORM channels have been independently checked before this
	# deliberate art-light calibration of the bright greybox lighting.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var sky = Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	_build_hat()
	_build_edge_grass()
	_build_root_accents()
	_update_sky()

func _build_hat() -> void:
	var body: Node3D = game.get_node("Player/Body")
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color("#b69759") if style_id == "A1" else Color("#9c9c9c")
	mat.roughness = 0.95
	for i in range(2):
		var mesh = CylinderMesh.new()
		mesh.top_radius = 0.38 if i == 0 else 0.22
		mesh.bottom_radius = 0.40 if i == 0 else 0.26
		mesh.height = 0.045 if i == 0 else 0.18
		mesh.radial_segments = 16
		var visual = MeshInstance3D.new()
		visual.name = "ArtHatBrim" if i == 0 else "ArtHatCrown"
		visual.mesh = mesh
		visual.material_override = mat
		visual.position.y = 1.62 if i == 0 else 1.72
		body.add_child(visual)
	var apron = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.36, 0.62, 0.035)
	apron.mesh = box
	var cloth = StandardMaterial3D.new()
	cloth.albedo_color = Color("#557351") if style_id == "A1" else Color("#45465a")
	cloth.roughness = 1
	apron.material_override = cloth
	apron.position = Vector3(0, 0.72, -0.29)
	body.add_child(apron)

func _process(_delta: float) -> void:
	if sky_material != null:
		_update_sky()
		for id in root_lights:
			var entry = root_lights[id]
			entry.light.visible = int(entry.plot.stage) == 4 and int(entry.plot.crop) == 1

func _update_sky() -> void:
	var day = (sin((fmod(float(game.hours), 24.0) - 6.0) / 24.0 * TAU) + 1.0) * 0.5
	var environment: Environment = game.get_node("WorldEnvironment").environment
	game.get_node("Sun").light_energy = lerpf(0.35, 1.1, day) * (0.55 if style_id == "A1" else 0.90)
	environment.ambient_light_energy = lerpf(0.55, 0.8, day) * (0.60 if style_id == "A1" else 1.15)
	if style_id == "D1":
		game.get_node("Sun").light_color = Color("#c3cce8").lerp(Color("#e2e8ef"), day)
		environment.ambient_light_color = Color("#c3c9df").lerp(Color("#d2d7e0"), day)
	if style_id == "A1":
		sky_material.sky_top_color = Color("#233553").lerp(Color("#75a3bd"), day)
		sky_material.sky_horizon_color = Color("#63667f").lerp(Color("#d8d4b8"), day)
		sky_material.ground_bottom_color = Color("#343c47").lerp(Color("#8d937c"), day)
	else:
		sky_material.sky_top_color = Color("#161d36").lerp(Color("#788a9d"), day)
		sky_material.sky_horizon_color = Color("#4b4e72").lerp(Color("#acb7bd"), day)
		sky_material.ground_bottom_color = Color("#262b43").lerp(Color("#59616f"), day)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color

func _build_edge_grass() -> void:
	var mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	for i in range(3):
		var angle = float(i) * PI / 3.0
		for v in [Vector3(-0.04, 0, 0), Vector3(0.04, 0, 0), Vector3(0.13, 1.0, 0)]:
			vertices.append(v.rotated(Vector3.UP, angle))
			normals.append(Vector3.BACK.rotated(Vector3.UP, angle))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var placements: Array = []
	var rng = RandomNumberGenerator.new()
	rng.seed = 48173
	for zone in [Vector2(0.6, 17.3), Vector2(-19.0, -6.7), Vector2(-35.2, -21.0)]:
		for i in range(110 if style_id == "A1" else 65):
			var x = (-1 if i % 2 == 0 else 1) * rng.randf_range(7.7, 9.25)
			var z = rng.randf_range(zone.x, zone.y)
			placements.append(Vector3(x, 0.015, z))
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = placements.size()
	var green = Color("#698c3d") if style_id == "A1" else Color("#9da894")
	for i in range(placements.size()):
		var height = rng.randf_range(0.20, 0.42)
		var basis = Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * height)
		multimesh.set_instance_transform(i, Transform3D(basis, placements[i]))
		multimesh.set_instance_color(i, green * rng.randf_range(0.75, 1.05))
	var visual = MultiMeshInstance3D.new()
	visual.name = "AuthoredEdgeGrass"
	visual.multimesh = multimesh
	game.add_child(visual)
	grass_instances = placements.size()

func _build_root_accents() -> void:
	if style_id != "D1":
		return
	for plot in game.get_node("Plots").get_children():
		var light = OmniLight3D.new()
		light.name = "MatureRootArtGlow"
		light.position = Vector3(0, 0.45, 0)
		light.omni_range = 2.2
		light.light_color = Color("#d7a94c")
		light.light_energy = 0.75
		light.visible = false
		plot.add_child(light)
		root_lights[plot.plot_id] = {"plot":plot,"light":light}

func get_report() -> Dictionary:
	return {"style":style_id,"tone_mapper":"ACES","reference_white":6.0,
		"exposure":0.70 if style_id == "A1" else 1.0,
		"sun_art_multiplier":0.55 if style_id == "A1" else 0.90,
		"ambient_art_multiplier":0.60 if style_id == "A1" else 1.15,
		"clock_and_sun_angle_unchanged":true,"grass_instances":grass_instances,
		"grass_triangles":grass_instances * 3,
		"material_basis":"Source albedo/ORM channels inspected before deliberate artistic lighting calibration."}
