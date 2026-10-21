extends Node3D
## Visual-only companion of _GreyboxArtLayer. All geometry belongs to this node.
## No colliders, labels, lights, crop writes, or dependency on new generated assets.
@export_enum("A1", "D1") var style_id: String = "A1"

const MAX_INSTANCES: int = 1100
const MAX_PROCEDURAL_TRIANGLES: int = 240000
const MAX_SOURCE_TRIANGLES: int = 60000
const ZONES: Array[Vector2] = [Vector2(0.6, 17.3), Vector2(-19.0, -6.7), Vector2(-35.2, -21.0)]
var assembled: bool = false
var assembly_errors: Array[String] = []
var _game: Node3D
var _art: Node3D
var _wait_seconds: float = 0.0
var _building: bool = false
var _build_after_frame: int = -1
var _rng := RandomNumberGenerator.new()
var _meshes: Dictionary = {}
var _colors: Dictionary = {}
var _batches: Dictionary = {}
var _beds: Array[Dictionary] = []
var _hidden: Dictionary = {}
var _source_ids: Array[String] = []
var _edge_placement_source: String = "none"
var _counts: Dictionary = {"plant_instances": 0, "batch_nodes": 0, "procedural_triangles": 0,
	"generated_instances": 0, "generated_triangles": 0, "bed_meshes": 0, "crop_meshes": 0,
	"ivy_strands": 0, "flowers": 0, "replaced_grass": 0}
var _material: StandardMaterial3D

func _ready() -> void:
	_game = get_parent() as Node3D
	process_priority = 130
	call_deferred("_try_build")

func _try_build() -> void:
	if assembled or _building or not assembly_errors.is_empty():
		return
	if _game == null:
		_fail("Attach PlantDetail directly under the gameplay Node3D.")
		return
	_art = _game.get_node_or_null("_GreyboxArtLayer") as Node3D
	if _art == null:
		# Preserve compatibility with a renamed production-layer node.
		for child in _game.get_children():
			var script: Script = child.get_script()
			if script != null and script.resource_path.ends_with("/production/garden_art.gd"):
				_art = child as Node3D
				break
	if _art == null or not bool(_art.get("assembled")):
		return
	if str(_art.get("style_id")) != style_id:
		_fail("PlantDetail style_id must match the production layer.")
		return
	# Sibling GardenLook.configure() may still be queued when art becomes ready.
	# Let its authored grass exist before assessing complete replacement.
	if _build_after_frame < 0:
		_build_after_frame = Engine.get_process_frames() + 2
		return
	if Engine.get_process_frames() < _build_after_frame:
		return
	_building = true
	_rng.seed = 310721
	_palette()
	_build_families()
	_build_boundary()
	_replace_old_grass()
	_flush_batches()
	_build_beds()
	_reuse_source_foliage()
	if assembly_errors.is_empty():
		assembled = true
		_sync_beds()
	else:
		# Partial construction never removes the previous visual treatment.
		for old in _hidden:
			if is_instance_valid(old):
				old.visible = _hidden[old]
		_hidden.clear()
		visible = false
	_building = false

func _process(delta: float) -> void:
	if assembled:
		_sync_beds()
	elif assembly_errors.is_empty():
		_wait_seconds += delta
		if _wait_seconds > 20.0:
			_fail("Production art was not assembled within 20 seconds.")
		else:
			_try_build()

func _palette() -> void:
	var moon: bool = style_id == "D1"
	_colors = {
		"leaf": Color("#71837e") if moon else Color("#608b39"),
		"light": Color("#9aa99c") if moon else Color("#a4bb52"),
		"dark": Color("#3e4a52") if moon else Color("#375f30"),
		"stem": Color("#828c79") if moon else Color("#718344"),
		"petal": Color("#f1d8a4") if moon else Color("#fff0cd"),
		"heart": Color("#d69d53") if moon else Color("#d9ad45"),
		"earth": Color("#342d32") if moon else Color("#553721"),
		"clod": Color("#625044") if moon else Color("#916344"),
	}
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.roughness = 0.91
	_material.metallic_specular = 0.18

func _begin() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

func _tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Explicit normals keep the shallow folded leaves and broad soil faces readable.
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	for point in [a, b, c]:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(point)

func _finish(surface: SurfaceTool) -> ArrayMesh:
	surface.set_material(_material)
	return surface.commit()

func _leaf(surface: SurfaceTool, base: Vector3, direction: Vector3, length: float,
		width: float, lift: float, color: Color) -> void:
	var forward: Vector3 = direction.normalized()
	var side: Vector3 = forward.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	# Six stations, a raised midrib and cupped margins; no crossed grass cards.
	for segment in range(6):
		var t0: float = float(segment) / 6.0
		var t1: float = float(segment + 1) / 6.0
		var centers: Array[Vector3] = []
		var widths: Array[float] = []
		for t in [t0, t1]:
			centers.append(base + forward * length * t + Vector3.UP * (sin(t * PI * 0.88) * lift - t * t * length * 0.12))
			widths.append(pow(sin(t * PI), 0.72) * width)
		for sign_side in [-1.0, 1.0]:
			var e0: Vector3 = centers[0] + side * widths[0] * sign_side - Vector3.UP * widths[0] * 0.22
			var e1: Vector3 = centers[1] + side * widths[1] * sign_side - Vector3.UP * widths[1] * 0.22
			var shade: Color = color.lightened(0.09) if sign_side < 0.0 else color
			_tri(surface, centers[0], e0, e1, shade)
			_tri(surface, centers[0], e1, centers[1], shade)

func _curve(surface: SurfaceTool, points: Array[Vector3], radius: float, color: Color) -> void:
	for index in range(points.size() - 1):
		var axis: Vector3 = (points[index + 1] - points[index]).normalized()
		var side: Vector3 = axis.cross(Vector3.FORWARD).normalized()
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		var up: Vector3 = axis.cross(side).normalized()
		for face in range(5):
			var a: float = TAU * float(face) / 5.0
			var b: float = TAU * float(face + 1) / 5.0
			var r0: Vector3 = (side * cos(a) + up * sin(a)) * radius
			var r1: Vector3 = (side * cos(b) + up * sin(b)) * radius
			_tri(surface, points[index] + r0, points[index + 1] + r0, points[index + 1] + r1, color)
			_tri(surface, points[index] + r0, points[index + 1] + r1, points[index] + r1, color)

func _build_families() -> void:
	for variant in range(3):
		var broad: SurfaceTool = _begin()
		for leaf_index in range(7 + variant):
			var angle: float = float(leaf_index) * 2.399 + variant * 0.7
			var direction := Vector3(cos(angle), 0.12, sin(angle))
			_leaf(broad, Vector3(0, 0.045, 0), direction, 0.42 + 0.08 * (leaf_index % 3),
				0.10 + 0.018 * variant, 0.26 + 0.07 * (leaf_index % 2),
				_colors.light if leaf_index % 3 == 0 else _colors.leaf)
		_meshes["broad%d" % variant] = _finish(broad)
		var fern: SurfaceTool = _begin()
		for frond in range(3):
			var angle: float = float(frond) * 2.399 + float(variant)
			var direction := Vector3(cos(angle), 0, sin(angle))
			var lateral: Vector3 = direction.cross(Vector3.UP)
			var points: Array[Vector3] = []
			for step in range(9):
				var t: float = float(step) / 8.0
				points.append(direction * t * 0.66 + Vector3.UP * (sin(t * PI * 0.72) * 0.53 + 0.03))
			_curve(fern, points, 0.008, _colors.stem)
			for step in range(1, 7):
				var t: float = float(step) / 8.0
				for sign_side in [-1.0, 1.0]:
					_leaf(fern, points[step], lateral * sign_side + direction * 0.50,
						0.22 * sin(t * PI) + 0.03, 0.035, 0.035, _colors.light if step % 3 == 0 else _colors.leaf)
		_meshes["fern%d" % variant] = _finish(fern)
		var ivy: SurfaceTool = _begin()
		var strand: Array[Vector3] = []
		for step in range(13):
			var t: float = float(step) / 12.0
			strand.append(Vector3(sin(t * 5.0 + variant) * 0.13, -t * (1.25 + variant * 0.28), t * 0.09))
		_curve(ivy, strand, 0.012, _colors.stem)
		for step in range(1, 12):
			var sign_side: float = -1.0 if step % 2 == 0 else 1.0
			_leaf(ivy, strand[step], Vector3(sign_side, -0.4, 0.3), 0.21,
				0.095, 0.045, _colors.light if step % 3 == 0 else _colors.leaf)
		_meshes["ivy%d" % variant] = _finish(ivy)
		var flowers: SurfaceTool = _begin()
		for flower_index in range(3):
			var at := Vector3(cos(flower_index * 2.4) * 0.17, 0, sin(flower_index * 2.4) * 0.17)
			var height: float = 0.30 + 0.10 * ((flower_index + variant) % 3)
			var top: Vector3 = at + Vector3(0.06, height, 0.035)
			_curve(flowers, [at, at + Vector3(-0.02, height * 0.55, 0), top], 0.009, _colors.stem)
			_leaf(flowers, at + Vector3.UP * height * 0.35, Vector3(-1, 0.2, 0.3), 0.18, 0.055, 0.03, _colors.leaf)
			var petal_count: int = 5 if style_id == "D1" else 8
			for petal in range(petal_count):
				var a: float = TAU * float(petal) / float(petal_count)
				_leaf(flowers, top, Vector3(cos(a), 0, sin(a)), 0.075 if style_id == "D1" else 0.115,
					0.032, 0.018, _colors.petal)
			for face in range(8):
				var a: float = TAU * float(face) / 8.0
				var b: float = TAU * float(face + 1) / 8.0
				_tri(flowers, top + Vector3.UP * 0.025, top + Vector3(cos(a), 0.08, sin(a)) * 0.031,
					top + Vector3(cos(b), 0.08, sin(b)) * 0.031, _colors.heart)
		_meshes["flower%d" % variant] = _finish(flowers)

func _safe_decoration(at: Vector3, radius: float = 0.65, plot_clearance: float = 2.6) -> bool:
	if absf(at.x) - radius < 2.2:
		return false
	var plots: Node = _game.get_node_or_null("Plots")
	if plots != null:
		for plot in plots.get_children():
			var center: Vector3 = _game.to_local(plot.global_position)
			if Vector2(at.x - center.x, at.z - center.z).length() < plot_clearance + radius:
				return false
	return true

func _place(key: String, at: Vector3, size: float, yaw: float, zone: int) -> bool:
	var mesh: ArrayMesh = _meshes[key]
	var triangles: int = mesh.surface_get_array_len(0) / 3
	if int(_counts.plant_instances) >= MAX_INSTANCES or int(_counts.procedural_triangles) + triangles > MAX_PROCEDURAL_TRIANGLES:
		_fail("Plant geometry exceeded the declared budget.")
		return false
	var batch_key: String = "%d_%s" % [zone, key]
	if not _batches.has(batch_key):
		_batches[batch_key] = {"mesh": mesh, "transforms": []}
	var local: Transform3D = global_transform.affine_inverse() * _game.global_transform
	_batches[batch_key].transforms.append(local * Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at))
	_counts.plant_instances += 1
	_counts.procedural_triangles += triangles
	return true

func _build_boundary() -> void:
	for zone_index in range(ZONES.size()):
		var zone: Vector2 = ZONES[zone_index]
		for side in [-1.0, 1.0]:
			# Unequal spacing and grouped companions form pockets, not a planted row.
			for cluster in range(13):
				var z: float = lerpf(zone.x + 0.45, zone.y - 0.45, (cluster + _rng.randf_range(0.12, 0.85)) / 13.0)
				var at := Vector3(side * _rng.randf_range(7.95, 8.95), 0.025, z)
				if not _safe_decoration(at, 0.72):
					continue
				_place("broad%d" % (cluster % 3), at, _rng.randf_range(0.8, 1.18), _rng.randf() * TAU, zone_index)
				var companion: Vector3 = at + Vector3(-side * 0.25, 0, 0.31)
				_place("fern%d" % ((cluster + zone_index) % 3), companion, _rng.randf_range(0.58, 0.92), _rng.randf() * TAU, zone_index)
				if cluster % 2 == 0:
					_place("flower%d" % (cluster % 3), at + Vector3(-side * 0.32, 0, -0.22), 0.85, cluster * 1.37, zone_index)
					_counts.flowers += 3
				if cluster % 2 == 1:
					# Drapes outside the original x=9.8 boundary, below its cap.
					_place("ivy%d" % (cluster % 3), Vector3(side * 9.86, 0.91, z), 1.0, side * PI * 0.5, zone_index)
					_counts.ivy_strands += 1
			# Trench-facing cascades remain entirely outside the protected bridge route.
			if zone_index < 2:
				var bank: float = -0.08 if zone_index == 0 else -5.92
				for offset in [4.0, 6.2, 8.4]:
					_place("ivy%d" % (int(offset) % 3), Vector3(side * offset, -0.06, bank), 1.22,
						0.0 if zone_index == 0 else PI, zone_index)
					_counts.ivy_strands += 1

func _replace_old_grass() -> void:
	var world: Node = _game.get_node_or_null("World")
	if world != null:
		for owner in world.get_children():
			var old: Node3D = owner.get_node_or_null("ProductionGrass")
			if old == null:
				continue
			var at: Vector3 = _game.to_local(old.global_position)
			if not _safe_decoration(at, 0.40, 1.5):
				continue
			if _place("broad%d" % (_counts.replaced_grass % 3), at, 0.76, _rng.randf() * TAU, 3):
				_hide_replaced(old)
				_counts.replaced_grass += 1
	var edge: MultiMeshInstance3D = _game.get_node_or_null("AuthoredEdgeGrass") as MultiMeshInstance3D
	if edge == null or edge.multimesh == null:
		return
	# Cover every old instance with a folded low rosette before hiding the old batch.
	# If an original location conflicts with a protected interaction envelope, retain
	# that whole old batch instead of claiming it has been completely replaced.
	var positions: Array[Vector3] = []
	var headless_positions: Array[Vector3] = []
	# The headless dummy renderer returns identity for MultiMesh transform reads.
	# Reconstruct only the known production grass family, with its exact seed,
	# count and position-generation order; never infer arbitrary imported layouts.
	var look: Node = _game.get_node_or_null("_GardenLook")
	var look_script: Script = look.get_script() if look != null else null
	var expected_count: int = 330 if style_id == "A1" else 195
	if DisplayServer.get_name() == "headless" and edge.multimesh.instance_count == expected_count and look_script != null and look_script.resource_path.ends_with("/production/garden_look.gd"):
		var source_rng := RandomNumberGenerator.new()
		source_rng.seed = 48173
		for zone in ZONES:
			for index in range(expected_count / 3):
				var x: float = (-1.0 if index % 2 == 0 else 1.0) * source_rng.randf_range(7.7, 9.25)
				headless_positions.append(Vector3(x, 0.015, source_rng.randf_range(zone.x, zone.y)))
	_edge_placement_source = "production_seed_48173_headless" if not headless_positions.is_empty() else "live_multimesh_transforms"
	for index in range(edge.multimesh.instance_count):
		var source_at: Vector3 = headless_positions[index] if not headless_positions.is_empty() else edge.multimesh.get_instance_transform(index).origin
		var at: Vector3 = _game.to_local(edge.to_global(source_at))
		if not _safe_decoration(at, 0.28, 1.5):
			return
		positions.append(at)
	var complete: bool = true
	for index in range(positions.size()):
		var placed: bool = _place("broad%d" % (index % 3), positions[index], _rng.randf_range(0.36, 0.52), _rng.randf() * TAU, 4 + index / 110)
		complete = complete and placed
	if complete:
		_hide_replaced(edge)
		_counts.replaced_grass += positions.size()

func _hide_replaced(old: Node3D) -> void:
	_hidden[old] = old.visible
	old.visible = false

func _flush_batches() -> void:
	for key in _batches:
		var entry: Dictionary = _batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = entry.mesh
		multi.instance_count = entry.transforms.size()
		for index in range(multi.instance_count):
			multi.set_instance_transform(index, entry.transforms[index])
		var visual := MultiMeshInstance3D.new()
		visual.name = "PlantBatch_" + key
		visual.multimesh = multi
		add_child(visual)
		_counts.batch_nodes += 1
	_batches.clear()

func _soil_mesh(cultivated: bool) -> ArrayMesh:
	var surface: SurfaceTool = _begin()
	var cells: int = 24
	for x in range(cells):
		for z in range(cells):
			var points: Array[Vector3] = []
			for corner in [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]:
				var px: float = -1.08 + corner.x * 2.16 / float(cells)
				var pz: float = -1.08 + corner.y * 2.16 / float(cells)
				var irregular: float = sin(px * 29.0 + cos(pz * 18.0)) * sin(pz * 24.0) * 0.003
				var ridge: float = pow(0.5 + 0.5 * cos(px * TAU / 0.53), 2.0) * 0.035 if cultivated else 0.005 * sin(px * 12.0 + pz * 7.0)
				points.append(Vector3(px, 0.008 + ridge + irregular, pz))
			var tint: Color = _colors.earth.lerp(_colors.clod, 0.12 + 0.035 * (0.5 + 0.5 * sin(x * 0.7 + z * 0.4)))
			_tri(surface, points[0], points[1], points[2], tint)
			_tri(surface, points[0], points[2], points[3], tint)
	return _finish(surface)

func _crop_mesh(species: int, stage_index: int) -> ArrayMesh:
	var surface: SurfaceTool = _begin()
	var mature: bool = stage_index == 2
	var extent: float = [0.24, 0.39, 0.54][stage_index]
	var count: int = [3, 5, 6][stage_index]
	for index in range(count):
		var angle: float = index * 2.399 + species * 0.8
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var base: Vector3 = direction * (0.16 if species == 0 else 0.28)
		base.y = 0.04 + (0.07 * (index % 2) if species == 0 else 0.0)
		_leaf(surface, base, direction, extent, extent * (0.30 if species == 0 else 0.14),
			extent * (0.65 if species == 0 else 0.85), _colors.light if index % 3 == 0 else _colors.leaf)
		if species == 0 and stage_index >= 1 and index % 2 == 0:
			var curl: Array[Vector3] = []
			for step in range(15):
				var t: float = float(step) / 14.0
				var radius: float = (1.0 - t * 0.67) * 0.13
				curl.append(direction * (extent * 0.72 + radius * sin(t * TAU)) +
					Vector3.UP * (0.12 + t * (0.38 if mature else 0.24)) +
					direction.cross(Vector3.UP) * radius * cos(t * TAU))
			_curve(surface, curl, 0.010, _colors.stem)
	return _finish(surface)

func _build_beds() -> void:
	var art_plots: Dictionary = _art.get("_plots")
	var hard: ArrayMesh = _soil_mesh(false)
	var tilled: ArrayMesh = _soil_mesh(true)
	for species in range(2):
		for stage_index in range(3):
			_meshes["crop_%d_%d" % [species, stage_index]] = _crop_mesh(species, stage_index)
	for id in art_plots:
		var source: Dictionary = art_plots[id]
		var bed := Node3D.new()
		bed.name = "BedDetail_" + str(id)
		add_child(bed)
		var earth := MeshInstance3D.new()
		earth.name = "SculptedSoil"
		earth.position.y = float(source.ground_top) + 0.026
		earth.mesh = hard
		bed.add_child(earth)
		var leaves := MeshInstance3D.new()
		leaves.name = "StageLeafAccents"
		leaves.position.y = float(source.ground_top) + 0.04
		leaves.visible = false
		bed.add_child(leaves)
		_beds.append({"owner": source.owner, "root": bed, "earth": earth, "leaves": leaves,
			"hard": hard, "tilled": tilled, "signature": "", "visual_stage": "none"})
		_counts.bed_meshes += 1
		_counts.crop_meshes += 1
		# Reserve worst-case active crop triangles, in addition to the soil grid.
		_counts.procedural_triangles += 1152 + maxi(_meshes.crop_0_2.surface_get_array_len(0), _meshes.crop_1_2.surface_get_array_len(0)) / 3
	if int(_counts.procedural_triangles) > MAX_PROCEDURAL_TRIANGLES:
		_fail("Bed detail exceeded the procedural triangle budget.")

func _sync_beds() -> void:
	for entry in _beds:
		var plot: Node3D = entry.owner
		if not is_instance_valid(plot):
			entry.root.visible = false
			continue
		entry.root.global_transform = plot.global_transform
		entry.root.visible = plot.is_visible_in_tree()
		var stage: int = int(plot.get("stage"))
		var species: int = int(plot.get("crop"))
		var growth: float = float(plot.get("growth"))
		var detail_stage: int = 2 if stage == 4 else (1 if growth >= 1.5 else 0)
		var signature: String = "%d:%d:%d" % [stage, species, detail_stage]
		if entry.signature == signature:
			continue
		entry.signature = signature
		entry.earth.mesh = entry.hard if stage == 0 else entry.tilled
		entry.leaves.visible = stage >= 3 and species in [0, 1]
		entry.visual_stage = ["sprout", "leafy", "mature"][detail_stage] if entry.leaves.visible else "none"
		if entry.leaves.visible:
			entry.leaves.mesh = _meshes["crop_%d_%d" % [species, detail_stage]]

func _reuse_source_foliage() -> void:
	var models: RefCounted = _art.get("_models")
	var sources: Dictionary = models.get("sources")
	if not sources.has("vine_leafy"):
		return
	var triangles: int = int(sources.vine_leafy.triangles)
	# The sanitized generated leaf family is an occasional background anchor.
	# Its lack of mature flowers/fruit and remote placement avoid harvest cues.
	for index in range(6):
		if int(_counts.generated_triangles) + triangles > MAX_SOURCE_TRIANGLES:
			break
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var at := Vector3(side * 8.8, 0.025, [13.1, 4.2, -9.5, -16.8, -24.0, -32.0][index])
		if not _safe_decoration(at, 0.8):
			continue
		var id: String = "r3_boundary_foliage_%s_%d" % [style_id, index]
		var visual: Node3D = models.call("instantiate_model", "vine_leafy",
			Vector3(1.10, 0.66 + index % 3 * 0.09, 1.10), id, 37.0 + index * 137.5)
		if visual == null:
			continue
		add_child(visual)
		visual.global_position = _game.to_global(at)
		_source_ids.append(id)
		_counts.generated_instances += 1
		_counts.generated_triangles += triangles

func get_report() -> Dictionary:
	var stages: Dictionary = {}
	for entry in _beds:
		if is_instance_valid(entry.owner):
			stages[str(entry.owner.name)] = entry.visual_stage
	return {"style": style_id, "assembled": assembled, "ready": assembled,
		"status": "assembled_pending_native_review" if assembled else ("waiting_for_production" if assembly_errors.is_empty() else "blocked"),
		"errors": assembly_errors.duplicate(), "assembly_errors": assembly_errors.duplicate(),
		"instance_counts": _counts.duplicate(), "active_crop_accents": stages,
		"edge_placement_source": _edge_placement_source,
		"budgets": {"plant_instances": MAX_INSTANCES, "procedural_triangles": MAX_PROCEDURAL_TRIANGLES, "generated_triangles": MAX_SOURCE_TRIANGLES},
		"hidden_replaced_nodes": _hidden.size(), "main_path_clearance": 2.2,
		"decoration_plot_exclusion_radius": 2.6, "labels_added": 0, "colliders_added": 0,
		"gameplay_writes": 0, "final_accepted": false}

func _fail(message: String) -> void:
	if not assembly_errors.has(message):
		assembly_errors.append(message)
		push_error("PlantDetail: " + message)

func _exit_tree() -> void:
	for old in _hidden:
		if is_instance_valid(old):
			old.visible = _hidden[old]
	if is_instance_valid(_art):
		var models: RefCounted = _art.get("_models")
		if models != null:
			for id in _source_ids:
				models.get("normalization_bounds").erase(id)
