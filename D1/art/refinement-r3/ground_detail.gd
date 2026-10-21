extends Node3D
## R3 visual-only ground. Attach directly to the original game, after its art layer.
## Never creates bodies, collision, gameplay state, texture imports, or external assets.
const DETAIL_SHADER = preload("res://art/refinement-r3/ground_detail.gdshader")
const ZONES = [
	{"name": "StartingGarden", "rect": Rect2(-10, 0, 20, 18)},
	{"name": "StoneGarden", "rect": Rect2(-10, -20, 20, 14)},
	{"name": "SourceGarden", "rect": Rect2(-10, -36, 20, 16)},
]
const PLOT_CENTERS = [
	Vector2(-4, 9), Vector2(-4, 4), Vector2(0, 2.6), Vector2(4.5, -13),
	Vector2(0, -17), Vector2(-4, -26), Vector2(4, -26),
	Vector2(-4, -31), Vector2(4, -31),
]
const PLOT_IDS = [
	"PracticeA", "PracticeB", "VineLock", "MiddleBed", "RootLock",
	"FinalA", "FinalB", "FinalC", "FinalD",
]
# Authored pedestrian desire lines: approach the beds from their open sides.
# Segments do not connect across the bridge void. CPU scatter uses the same data.
const WEAR_SEGMENTS = [
	Vector4(0, 17, 0.8, 11), Vector4(0.8, 11, 0.8, 6),
	Vector4(0.8, 6, 2.2, 2.7), Vector4(2.2, 2.7, 0, 0.1),
	Vector4(0.8, 10.8, -4.2, 10.8), Vector4(0.8, 5.8, -4.2, 5.8),
	Vector4(0, -6.1, -1.4, -11), Vector4(-1.4, -11, -2.1, -17),
	Vector4(-2.1, -17, 0, -19.9), Vector4(-1.4, -11, 4.6, -11.2),
	Vector4(0, -20.1, 0.5, -24), Vector4(0.5, -24, 0, -28.6),
	Vector4(0, -28.6, -1.8, -31), Vector4(-1.8, -31, 0, -34.5),
	Vector4(-5, -24.2, 5, -24.2), Vector4(-5, -29.2, 5, -29.2),
	Vector4(2.1, 2.8, 5.8, 4.2), Vector4(-2.1, -17, -5.5, -16.5),
]
# Deliberately asymmetric outlines, not scaled cubes or identical hexagons.
const STONE_OUTLINES = [
	[Vector2(-0.53, -0.22), Vector2(-0.21, -0.47), Vector2(0.37, -0.40),
		Vector2(0.55, -0.06), Vector2(0.26, 0.42), Vector2(-0.36, 0.37)],
	[Vector2(-0.48, -0.34), Vector2(0.04, -0.51), Vector2(0.41, -0.24),
		Vector2(0.31, 0.05), Vector2(0.50, 0.20), Vector2(0.13, 0.42), Vector2(-0.51, 0.19)],
	[Vector2(-0.54, -0.16), Vector2(-0.33, -0.44), Vector2(0.36, -0.36),
		Vector2(0.55, 0.13), Vector2(0.09, 0.48), Vector2(-0.36, 0.27)],
]

@export_enum("A1", "D1") var style_id: String = "A1"

var game: Node3D
var build_ready: bool = false
var errors: Array[String] = []
var _started: bool = false
var _rng := RandomNumberGenerator.new()
var _materials: Array[ShaderMaterial] = []
var _overrides: Array[Dictionary] = []
var _beds: Array[Dictionary] = []
var _exclusions: Array[Rect2] = []
var _buffers: Dictionary = {}
var _metrics: Dictionary = {
	"ground_materials": 0, "stone_pieces": 0, "moss_islands": 0,
	"seam_moss_strips": 0, "pebbles": 0, "dry_leaves": 0, "slate_chips": 0,
	"furrow_beds": 0, "furrow_ridges": 0, "triangles": 0, "mesh_batches": 0,
	"max_tread_y": 0.0, "rejected_footprints": 0,
}

func _ready() -> void:
	game = get_parent() as Node3D
	process_priority = 130
	# One extra deferred hop lets sibling production assemblies finish first.
	call_deferred("_after_sibling_ready")

func _after_sibling_ready() -> void:
	call_deferred("build")

func build() -> void:
	if _started:
		return
	_started = true
	if game == null or style_id not in ["A1", "D1"]:
		errors.append("GroundDetail needs a direct Node3D game parent and style A1/D1.")
		return
	if not transform.is_equal_approx(Transform3D.IDENTITY):
		errors.append("GroundDetail must have identity local transform under game.")
		return
	for zone in ZONES:
		var original := game.get_node_or_null("World/" + zone.name + "/Mesh") as MeshInstance3D
		if original == null or original.mesh == null:
			errors.append("Missing original ground mesh: " + zone.name)
			continue
		var bounds: AABB = (game.global_transform.affine_inverse() * original.global_transform) * original.get_aabb()
		var rectangle: Rect2 = zone.rect
		if not is_equal_approx(bounds.end.y, 0.0) or not Vector2(bounds.position.x, bounds.position.z).is_equal_approx(rectangle.position) or not Vector2(bounds.size.x, bounds.size.z).is_equal_approx(rectangle.size):
			errors.append("Original ground footprint/top differs from frozen R3 contract: " + zone.name)
	for i in range(PLOT_IDS.size()):
		var plot := game.get_node_or_null("Plots/" + PLOT_IDS[i]) as Node3D
		if plot == null or not Vector2(plot.position.x, plot.position.z).is_equal_approx(PLOT_CENTERS[i]):
			errors.append("Missing or moved original plot: " + PLOT_IDS[i])
		# Include lock runes and original target outlines in exclusion bounds.
		var half := Vector2(1.67, 1.47) if i in [2, 4] else Vector2(1.36, 1.36)
		_exclusions.append(Rect2(PLOT_CENTERS[i] - half, half * 2.0))
	_exclusions.append(Rect2(-1.35, -32.35, 2.7, 2.7)) # Source altar.
	if not errors.is_empty():
		return
	_rng.seed = 319041 if style_id == "A1" else 319109
	_make_materials()
	for zone in ZONES:
		var mesh := game.get_node("World/" + zone.name + "/Mesh") as MeshInstance3D
		_overrides.append({"node": mesh, "before": mesh.material_override})
		mesh.material_override = _materials[0]
		_metrics.ground_materials += 1
		var rectangle: Rect2 = zone.rect
		_buffers.clear()
		for kind in [1, 2, 4]:
			_buffers[kind] = _new_buffer()
		if style_id == "D1":
			_slate_field(rectangle.grow(-0.10))
		else:
			_garden_stones(rectangle)
			_garden_moss(rectangle)
		_scatter(rectangle)
		for kind in [1, 2, 4]:
			_flush(_buffers[kind], _materials[kind], self, zone.name + "_R3_" + str(kind))
	_build_furrows()
	_sync_furrows()
	build_ready = errors.is_empty()

func _make_materials() -> void:
	for kind in range(5):
		var material := ShaderMaterial.new()
		material.shader = DETAIL_SHADER
		material.set_shader_parameter("surface_kind", kind)
		material.set_shader_parameter("moon_style", style_id == "D1")
		material.set_shader_parameter("world_to_garden", game.global_transform.affine_inverse())
		material.set_shader_parameter("wear_segments", PackedVector4Array(WEAR_SEGMENTS))
		material.set_shader_parameter("bed_centers", PackedVector2Array(PLOT_CENTERS))
		material.set_shader_parameter("earth_color", Color("#806044") if style_id == "D1" else Color("#a37543"))
		material.set_shader_parameter("worn_color", Color("#596477") if style_id == "D1" else Color("#d1a063"))
		material.set_shader_parameter("moss_color", Color("#536044") if style_id == "D1" else Color("#71813b"))
		material.set_shader_parameter("side_color", Color("#414b61") if style_id == "D1" else Color("#8b7855"))
		_materials.append(material)

func _new_buffer() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(),
		"c": PackedColorArray(), "uv": PackedVector2Array()}

func _triangle(buffer: Dictionary, a: Vector3, b: Vector3, c: Vector3,
		color: Color, ua: Vector2 = Vector2.ZERO, ub: Vector2 = Vector2.ZERO,
		uc: Vector2 = Vector2.ZERO) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Normals point up even for a clipped polygon returned with opposite winding.
	if normal.y < 0.0:
		var swap := b
		b = c
		c = swap
		var swap_uv := ub
		ub = uc
		uc = swap_uv
		normal = -normal
	# Godot's front faces use clockwise winding. Keep the authored upward
	# normals; reversed winding made two-sided slate shade as its underside.
	buffer.v.append_array(PackedVector3Array([a, c, b]))
	buffer.n.append_array(PackedVector3Array([normal, normal, normal]))
	# Native side-by-side calibration: COLOR already follows the renderer's
	# vertex-colour conversion. Pre-converting here caused double darkening.
	buffer.c.append_array(PackedColorArray([color, color, color]))
	buffer.uv.append_array(PackedVector2Array([ua, uc, ub]))

func _flush(buffer: Dictionary, material: Material, owner_node: Node3D, label: String) -> void:
	if buffer.v.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffer.v
	arrays[Mesh.ARRAY_NORMAL] = buffer.n
	arrays[Mesh.ARRAY_COLOR] = buffer.c
	arrays[Mesh.ARRAY_TEX_UV] = buffer.uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	owner_node.add_child(visual)
	_metrics.triangles += buffer.v.size() / 3
	_metrics.mesh_batches += 1
	if owner_node == self:
		for v in buffer.v:
			_metrics.max_tread_y = maxf(_metrics.max_tread_y, v.y)

func _point3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

func _safe_point(p: Vector2, margin: float = 0.0) -> bool:
	var in_zone := false
	for zone in ZONES:
		if zone.rect.grow(-0.11 - margin).has_point(p):
			in_zone = true
			break
	if not in_zone:
		return false
	for rectangle in _exclusions:
		if rectangle.grow(margin).has_point(p):
			return false
	return true

func _safe_polygon(poly: PackedVector2Array) -> bool:
	for p in poly:
		if not _safe_point(p):
			_metrics.rejected_footprints += 1
			return false
	# Vertices alone miss a polygon spanning a protected bed corner.
	for rectangle in _exclusions:
		if not Geometry2D.intersect_polygons(poly, _rect_poly(rectangle)).is_empty():
			_metrics.rejected_footprints += 1
			return false
	return true

func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

func _wear_distance(p: Vector2) -> float:
	var distance := 100.0
	for segment in WEAR_SEGMENTS:
		var a := Vector2(segment.x, segment.y)
		var b := Vector2(segment.z, segment.w)
		distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return distance

func _flat_polygon(buffer: Dictionary, poly: PackedVector2Array, y: float, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(poly)
	for j in range(0, indices.size(), 3):
		_triangle(buffer, _point3(poly[indices[j]], y), _point3(poly[indices[j + 1]], y),
			_point3(poly[indices[j + 2]], y), color)

func _beveled_stone(poly: PackedVector2Array, color: Color, top: float) -> void:
	if poly.size() < 3:
		return
	var center := Vector2.ZERO
	for p in poly:
		center += p
	center /= float(poly.size())
	var inner := PackedVector2Array()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in poly:
		inner.append(p.lerp(center, 0.055))
		low = low.min(p)
		high = high.max(p)
	var size := (high - low).max(Vector2(0.01, 0.01))
	var buffer: Dictionary = _buffers[1]
	var triangles := Geometry2D.triangulate_polygon(inner)
	for i in range(0, triangles.size(), 3):
		var a := inner[triangles[i]]
		var b := inner[triangles[i + 1]]
		var c := inner[triangles[i + 2]]
		_triangle(buffer, _point3(a, top), _point3(b, top), _point3(c, top),
			color, (a - low) / size, (b - low) / size, (c - low) / size)
	for i in range(poly.size()):
		var next := (i + 1) % poly.size()
		var edge_color := color.darkened(0.18)
		edge_color.a = 0.0
		_triangle(buffer, _point3(poly[i], 0.002), _point3(poly[next], 0.002), _point3(inner[next], top),
			edge_color)
		_triangle(buffer, _point3(poly[i], 0.002), _point3(inner[next], top), _point3(inner[i], top),
			edge_color)
	_metrics.stone_pieces += 1

func _slate_field(rectangle: Rect2) -> void:
	var cols := 14
	var rows := int(ceil(rectangle.size.y / 1.27))
	var grid: Array[PackedVector2Array] = []
	for row in range(rows + 1):
		var line := PackedVector2Array()
		for col in range(cols + 1):
			var p := rectangle.position + Vector2(rectangle.size.x * col / cols, rectangle.size.y * row / rows)
			if col > 0 and col < cols:
				p.x += (0.28 if row % 2 == 0 else -0.28) + _rng.randf_range(-0.14, 0.14)
			if row > 0 and row < rows:
				p.y += _rng.randf_range(-0.19, 0.19)
			line.append(p)
		grid.append(line)
	for row in range(rows):
		for col in range(cols):
			var cell := PackedVector2Array([grid[row][col], grid[row][col + 1],
				grid[row + 1][col + 1], grid[row + 1][col]])
			var center := (cell[0] + cell[1] + cell[2] + cell[3]) * 0.25
			var outline := PackedVector2Array()
			# Eight worn corners plus a missing flake on one edge.
			for j in range(4):
				var corner := cell[j].lerp(center, 0.045)
				var previous := cell[(j + 3) % 4].lerp(center, 0.045)
				var next := cell[(j + 1) % 4].lerp(center, 0.045)
				outline.append(corner.lerp(previous, _rng.randf_range(0.045, 0.12)))
				outline.append(corner.lerp(next, _rng.randf_range(0.045, 0.12)))
				if j == (col + row) % 4:
					outline.append(corner.lerp(next, 0.43))
					outline.append(corner.lerp(next, 0.51).lerp(center, _rng.randf_range(0.06, 0.16)))
					outline.append(corner.lerp(next, 0.61))
			var pieces: Array[PackedVector2Array] = [outline]
			for exclusion in _exclusions:
				var remaining: Array[PackedVector2Array] = []
				for piece in pieces:
					remaining.append_array(Geometry2D.clip_polygons(piece, _rect_poly(exclusion)))
				pieces = remaining
			var color := Color("#737784").lerp(Color("#525f70"), _rng.randf())
			color = color.lightened(_rng.randf_range(0.0, 0.065))
			color.a = 1.0 if _rng.randf() < 0.38 else 0.0
			for piece in pieces:
				_beveled_stone(piece, color, _rng.randf_range(0.012, 0.021))
			# Green fragments follow actual shared mortar edges, not a square overlay.
			if _rng.randf() < 0.53:
				_seam_moss(cell[0], cell[1])
			if _rng.randf() < 0.38:
				_seam_moss(cell[0], cell[3])

func _seam_moss(a: Vector2, b: Vector2) -> void:
	var start := a.lerp(b, _rng.randf_range(0.08, 0.30))
	var end := a.lerp(b, _rng.randf_range(0.55, 0.93))
	var side := (b - a).normalized().orthogonal()
	var poly := PackedVector2Array()
	for i in range(6):
		poly.append(start.lerp(end, i / 5.0) + side * _rng.randf_range(0.009, 0.028))
	for i in range(5, -1, -1):
		poly.append(start.lerp(end, i / 5.0) - side * _rng.randf_range(0.008, 0.025))
	if _safe_polygon(poly):
		_flat_polygon(_buffers[2], poly, 0.003, Color("#667050").darkened(_rng.randf_range(0.0, 0.18)))
		_metrics.seam_moss_strips += 1

func _garden_stones(rectangle: Rect2) -> void:
	# Sparse old edging/stepping fragments. The warm path remains mostly open soil.
	var anchors := [
		Vector2(-8.5, 0.14), Vector2(-7.7, 0.20), Vector2(-8.3, 0.27),
		Vector2(8.5, 0.36), Vector2(7.9, 0.41), Vector2(8.4, 0.49),
		Vector2(-7.8, 0.73), Vector2(-8.5, 0.80), Vector2(7.9, 0.88),
		Vector2(2.5, 0.93), Vector2(3.3, 0.94), Vector2(-2.6, 0.04),
	]
	for i in range(anchors.size()):
		var p := Vector2(anchors[i].x, rectangle.position.y + anchors[i].y * rectangle.size.y)
		var poly := _outline_at(p, Vector2(_rng.randf_range(0.75, 1.15), _rng.randf_range(0.65, 1.0)), i)
		if _safe_polygon(poly):
			var color := Color("#b6aa83").lerp(Color("#918b70"), _rng.randf())
			color.a = 0.0
			_beveled_stone(poly, color, _rng.randf_range(0.013, 0.023))

func _outline_at(p: Vector2, size: Vector2, variant: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var angle := _rng.randf_range(-PI, PI)
	for v in STONE_OUTLINES[variant % STONE_OUTLINES.size()]:
		poly.append(p + (v * size).rotated(angle))
	return poly

func _garden_moss(rectangle: Rect2) -> void:
	# Composed islands at wall toes; varied open intervals prevent a lawn border.
	for anchor in [Vector2(-8.9, 0.12), Vector2(8.6, 0.20), Vector2(-8.2, 0.43),
			Vector2(8.9, 0.61), Vector2(-8.8, 0.78), Vector2(7.8, 0.90)]:
		var at := Vector2(anchor.x, rectangle.position.y + rectangle.size.y * anchor.y)
		for i in range(9):
			var p := at + Vector2(_rng.randf_range(-0.45, 0.45), _rng.randf_range(-1.0, 1.0))
			_moss_lobe(p, Vector2(_rng.randf_range(0.23, 0.65), _rng.randf_range(0.27, 0.76)))
	for i in range(PLOT_CENTERS.size()):
		var p: Vector2 = PLOT_CENTERS[i]
		if not rectangle.has_point(p):
			continue
		for side in [-1.0, 1.0]:
			for j in range(5):
				var half_x: float = _exclusions[i].size.x * 0.5
				var at := p + Vector2(side * (half_x + 0.29), -1.0 + j * 0.49)
				_moss_lobe(at, Vector2(0.23, _rng.randf_range(0.20, 0.31)))

func _moss_lobe(p: Vector2, size: Vector2) -> void:
	if _wear_distance(p) < 0.85:
		return
	var poly := PackedVector2Array()
	for j in range(18):
		var angle := TAU * j / 18.0
		var radius := _rng.randf_range(0.73, 1.12) * (1.0 + 0.12 * sin(angle * 5.0))
		poly.append(p + Vector2(cos(angle), sin(angle)) * size * radius)
	if not _safe_polygon(poly):
		return
	var base := Color("#74813c").lerp(Color("#92984b"), _rng.randf())
	_flat_polygon(_buffers[2], poly, 0.0035, base.darkened(0.11))
	var crown := PackedVector2Array()
	for v in poly:
		crown.append(v.lerp(p, 0.26))
	_flat_polygon(_buffers[2], crown, 0.005, base)
	_metrics.moss_islands += 1

func _scatter(rectangle: Rect2) -> void:
	var moon := style_id == "D1"
	for i in range(510 if not moon else 240):
		var p := rectangle.position + Vector2(_rng.randf() * rectangle.size.x, _rng.randf() * rectangle.size.y)
		var edge_distance := 10.0 - absf(p.x)
		var bed_distance := 100.0
		for bed in PLOT_CENTERS:
			bed_distance = minf(bed_distance, maxf(absf(p.x - bed.x), absf(p.y - bed.y)) - 1.3)
		# Litter collects at contacts and sheltered pockets; traversed centers stay quiet.
		if edge_distance > 2.3 and bed_distance > 0.8 and _rng.randf() > 0.14:
			continue
		if _wear_distance(p) < 0.9 and _rng.randf() > 0.08:
			continue
		if not _safe_point(p, 0.14):
			continue
		if not moon and i % 3 == 0:
			_leaf(p)
		else:
			var radius := _rng.randf_range(0.035, 0.10)
			var outline := _outline_at(p, Vector2(radius * 2.0, radius * 1.4), i)
			var color := Color("#9a9ca2") if moon else Color("#b6a17a")
			color = color.darkened(_rng.randf_range(0.0, 0.26))
			var low := 0.022 if moon else 0.003
			var top := 0.0245 if moon else _rng.randf_range(0.011, 0.022)
			var center := p + Vector2(radius * 0.12, -radius * 0.09)
			for j in range(outline.size()):
				_triangle(_buffers[4], _point3(outline[j], low),
					_point3(outline[(j + 1) % outline.size()], low), _point3(center, top),
					color.darkened(0.05 if j % 2 == 0 else 0.0))
			_metrics["slate_chips" if moon else "pebbles"] += 1

func _leaf(p: Vector2) -> void:
	var direction := Vector2.from_angle(_rng.randf_range(0, TAU))
	var side := direction.orthogonal()
	var length := _rng.randf_range(0.10, 0.18)
	var width := _rng.randf_range(0.025, 0.055)
	var tip := p + direction * length
	var tail := p - direction * length * 0.7
	var left := p + side * width - direction * length * 0.12
	var right := p - side * width + direction * length * 0.13
	if not _safe_polygon(PackedVector2Array([tail, left, tip, right])):
		return
	var base := Color("#a77d42").lerp(Color("#806844"), _rng.randf())
	_triangle(_buffers[4], _point3(tail, 0.004), _point3(left, 0.006), _point3(p, 0.016), base)
	_triangle(_buffers[4], _point3(left, 0.006), _point3(tip, 0.009), _point3(p, 0.016), base)
	_triangle(_buffers[4], _point3(tip, 0.009), _point3(right, 0.005), _point3(p, 0.016), base.darkened(0.16))
	_triangle(_buffers[4], _point3(right, 0.005), _point3(tail, 0.004), _point3(p, 0.016), base.darkened(0.16))
	_metrics.dry_leaves += 1

func _build_furrows() -> void:
	var layer := game.get_node_or_null("_GreyboxArtLayer")
	var production_plots: Dictionary = {}
	if layer != null:
		for property in layer.get_property_list():
			if property.name == "_plots":
				production_plots = layer.get("_plots")
				break
	for id in PLOT_IDS:
		var plot := game.get_node("Plots/" + id) as Node3D
		var support_y := 0.20 # Original Soil top from main.tscn.
		if production_plots.has(id):
			support_y = float(production_plots[id].get("ground_top", support_y))
		var root := Node3D.new()
		root.name = "R3GroundFurrows"
		plot.add_child(root)
		var buffer := _new_buffer()
		# Soft ridges have six cross-section samples and tapered, irregular ends.
		for ridge in range(4):
			var center_x := -0.75 + ridge * 0.5
			var ridge_color := Color("#765137") if style_id == "A1" else Color("#65504a")
			for z_step in range(23):
				for x_step in range(6):
					var points: Array[Vector3] = []
					for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
						var u: float = (x_step + corner.x) / 6.0
						var v: float = (z_step + corner.y) / 23.0
						var z := -1.04 + v * 2.08
						var x := center_x + (u - 0.5) * 0.40 + sin(v * 15.0 + ridge * 2.0) * 0.014
						var taper := sin(PI * v)
						var height := pow(sin(PI * u), 1.4) * taper * (0.013 + 0.004 * sin(v * 39.0 + ridge))
						points.append(Vector3(x, support_y + 0.002 + height, z))
					var tint := ridge_color.darkened((1.0 - sin(PI * (x_step + 0.5) / 6.0)) * 0.22)
					_triangle(buffer, points[0], points[1], points[2], tint)
					_triangle(buffer, points[0], points[2], points[3], tint)
			_metrics.furrow_ridges += 1
		_flush(buffer, _materials[3], root, "SoftSoilRidges")
		_beds.append({"plot": plot, "root": root, "support_y": support_y})
		_metrics.furrow_beds += 1

func _process(_delta: float) -> void:
	if build_ready:
		_sync_furrows()

func _sync_furrows() -> void:
	for bed in _beds:
		if is_instance_valid(bed.plot) and is_instance_valid(bed.root):
			# Read-only state reflection: HARD retains the existing hard-clod visual.
			bed.root.visible = int(bed.plot.get("stage")) >= 1

func get_report() -> Dictionary:
	var report := _metrics.duplicate(true)
	report.merge({
		"ready": build_ready, "style_id": style_id, "revision": "ground-r3",
		"errors": errors.duplicate(), "acceptance": "pending parent integration and user review",
		"tread_height_limit": 0.025, "original_top_y": 0.0,
		"zones": ["StartingGarden: x[-10,10] z[0,18]", "StoneGarden: x[-10,10] z[-20,-6]",
			"SourceGarden: x[-10,10] z[-36,-20]"],
		"bridge_gap_geometry": false, "physics_nodes_created": 0,
		"gameplay_state_writes": 0, "external_dependencies": [],
		"furrow_supports": _beds.map(func(bed: Dictionary) -> Dictionary:
			return {"plot": str(bed.plot.name), "local_support_y": bed.support_y}),
	})
	return report

func _exit_tree() -> void:
	# Removing this component restores only materials that it still owns.
	for entry in _overrides:
		if is_instance_valid(entry.node) and not _materials.is_empty() and entry.node.material_override == _materials[0]:
			entry.node.material_override = entry.before
	for bed in _beds:
		if is_instance_valid(bed.root):
			bed.root.queue_free()
