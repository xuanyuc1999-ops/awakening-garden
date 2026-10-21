extends Node3D
## Attach once under the original gameplay root. This layer owns appearance only.
const Models = preload("garden_models.gd")
const GroundShader = preload("garden_ground.gdshader")
const REQUIRED_MODELS: Array[String] = [
	"vine_seed", "vine_sprout", "vine_leafy", "vine_mature",
	"root_seed", "root_sprout", "root_leafy", "root_mature",
	"soil", "watering_can", "rock", "stele", "bridge", "tree",
]
const PLOT_IDS: Array[String] = [
	"PracticeA", "PracticeB", "VineLock", "MiddleBed", "RootLock",
	"FinalA", "FinalB", "FinalC", "FinalD",
]
const LOGICAL_STAGES: Array[String] = ["HARD", "TILLED", "SOWN", "GROWING", "MATURE"]

@export var manifest_path: String = ""
@export var style_id: String = "A1"

var assembled: bool = false
var assembly_errors: Array = []
var game: Node3D
var collider_before: int = 0
var collider_after: int = 0
var _models = Models.new()
var _started: bool = false
var _sync_enabled: bool = false
var _owned_roots: Array[Node3D] = []
var _hidden: Dictionary = {}
var _material_changes: Dictionary = {}
var _plots: Dictionary = {}
var _collider_ids: Array[int] = []
var _palette: Dictionary = {}
var _materials: Dictionary = {}
var _deck: MeshInstance3D
var _bridge_art: Node3D
var _bridge_structure: Node3D
var _manifest_hash: String = ""

func _ready() -> void:
	game = get_parent() as Node3D
	# Children become ready first; main._ready performs another plot.refresh().
	# Run once that work has finished. Render synchronization follows game._process.
	process_priority = 100
	call_deferred("assemble")

func assemble() -> void:
	if _sync_enabled:
		return
	if game == null or not game.is_node_ready():
		_error("Attach GardenArt directly under the ready original gameplay root.")
		return
	_started = true
	assembly_errors.clear()
	_models.clear()
	_manifest_hash = ""
	_colliders(game, _collider_ids)
	collider_before = _collider_ids.size()
	collider_after = collider_before
	_validate_owners()
	if not FileAccess.file_exists(manifest_path):
		_error("Missing production manifest: " + manifest_path)
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(manifest_path)) != OK:
		_error("Invalid manifest JSON: " + parser.get_error_message())
		return
	var manifest: Variant = parser.data
	if not manifest is Dictionary:
		_error("Manifest root must be an object.")
		return
	if style_id not in ["A1", "D1"] or manifest.get("style", "") != style_id:
		_error("Manifest style must match exported style_id (A1 or D1).")
		return
	_manifest_hash = FileAccess.get_sha256(manifest_path)
	var entries: Variant = manifest.get("models", {})
	if not entries is Dictionary:
		_error("Manifest models must be an object.")
		return
	for key in REQUIRED_MODELS:
		if not entries.has(key) or not entries[key] is Dictionary:
			_error("Missing mandatory model entry: " + key)
		else:
			_models.load_model(key, entries[key])
	for message in _models.errors:
		_error(message)
	# Missing/invalid assets never become substitute art or a final assembly.
	# The original playable presentation remains available until all assets pass.
	if not assembly_errors.is_empty():
		return
	_create_palette()
	_build_world()
	_build_mechanisms()
	_build_player_and_pickup()
	for plot_id in PLOT_IDS:
		_build_plot(game.get_node("Plots/" + plot_id))
	_build_revival()
	_sync_enabled = true
	synchronize_state()
	var after_ids: Array[int] = []
	_colliders(game, after_ids)
	collider_after = after_ids.size()
	if _collider_ids != after_ids:
		_error("Art assembly changed the collider inventory.")
	assembled = assembly_errors.is_empty()
	if assembled and game.get("hud") != null:
		game.get("hud").title_label.text = "苏醒园地 / " + ("陶土暖园" if style_id == "A1" else "月下荆园")
	if not assembled:
		_remove_visual_layer()

func _validate_owners() -> void:
	var required: Array[String] = [
		"World", "Plots", "Player/Body/Tool/Mesh",
		"World/StartingGarden/Mesh", "World/StoneGarden/Mesh", "World/SourceGarden/Mesh",
		"Player/Body/Capsule",
		"Mechanisms/Bridge/Body/CollisionShape3D", "Mechanisms/Bridge/Planks",
		"Mechanisms/Bridge/VineRailLeft/Mesh", "Mechanisms/Bridge/VineRailRight/Mesh",
		"Mechanisms/Gate/Stones", "Mechanisms/Gate/Body/CollisionShape3D",
		"Mechanisms/Altar/SourceStone/Mesh", "Mechanisms/Altar/Base/Mesh",
		"Pickups/RootSeeds/Crate/Mesh", "Pickups/RootSeeds/SeedMark/Mesh", "Revival",
	]
	for plot_id in PLOT_IDS:
		required.append("Plots/" + plot_id + "/Soil")
		required.append("Plots/" + plot_id + "/CropVisual")
	for index in range(4):
		required.append("Mechanisms/Gate/Stones/Stone%d/Mesh" % index)
	for path in required:
		if not game.has_node(path):
			_error("Missing original visual owner: " + path)
	for sibling in game.get_children():
		if sibling == self:
			continue
		var script: Script = sibling.get_script()
		if script != null and (script.resource_path.ends_with("/art_proxy.gd") or script.resource_path.ends_with("/garden_art.gd")):
			_error("Use one art layer per scene; another proxy/production layer is attached.")
	if game.has_node("Plots") and game.get_node("Plots").get_child_count() != 9:
		_error("Expected the original nine plot owners.")
	if game.has_node("Mechanisms/Gate/Stones") and game.get_node("Mechanisms/Gate/Stones").get_child_count() != 4:
		_error("Expected the original four rubble owners.")
	if game.has_node("Mechanisms/Bridge/Planks") and game.get_node("Mechanisms/Bridge/Planks").get_child_count() != 10:
		_error("Expected the original ten animated plank owners.")

func _create_palette() -> void:
	var moon: bool = style_id == "D1"
	_palette = {
		"earth": Color("#4a526b") if moon else Color("#b99163"),
		"earth_patch": Color("#62677b") if moon else Color("#d8a16d"),
		"soil": Color("#39333d") if moon else Color("#765137"),
		"stone": Color("#353d49") if moon else Color("#8b7855"),
		"rim": Color("#8589a0") if moon else Color("#b56840"),
		"leaf": Color("#b8cab1") if moon else Color("#9bb875"),
		"vine": Color("#6f796f") if moon else Color("#5b8049"),
		"root": Color("#d7b46b") if moon else Color("#d8a16d"),
		"wood": Color("#6f694e") if moon else Color("#957452"),
		"cream": Color("#b8b9c4") if moon else Color("#e5d5ab"),
	}
	for key in _palette:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _palette[key]
		mat.roughness = 0.94
		_materials[key] = mat

func _build_world() -> void:
	var world: Node3D = game.get_node("World")
	var ground := ShaderMaterial.new()
	ground.shader = GroundShader
	ground.set_shader_parameter("base_color", _palette.earth)
	ground.set_shader_parameter("patch_color", _palette.earth_patch)
	ground.set_shader_parameter("edge_color", Color("#637b41") if style_id == "A1" else Color("#3c4952"))
	ground.set_shader_parameter("side_color", _palette.stone)
	for owner in world.get_children():
		var owner_name: String = str(owner.name)
		if owner_name.ends_with("Grid"):
			_hide(owner)
			continue
		var original: MeshInstance3D = owner.get_node_or_null("Mesh")
		if original == null:
			continue
		if owner_name in ["StartingGarden", "StoneGarden", "SourceGarden"]:
			_set_authored_material(original, ground)
		elif "West" in owner_name or "East" in owner_name or owner_name.ends_with("Boundary"):
			_set_authored_material(original, _materials.stone)
		elif owner_name.begins_with("DiscardedTimber"):
			_set_authored_material(original, _materials.wood)
			var trim: Node3D = _root(owner, "ProductionTimberBinding")
			for x in [-0.8, 0.8]:
				_box(trim, Vector3(0.08, 0.37, 0.42), Vector3(x, 0, 0), "rim")
		elif owner_name.begins_with("Weed"):
			_hide(original)
			_grass(_root(owner, "ProductionGrass"), Vector3(0, -0.25, 0), 0.45)
		elif owner_name.begins_with("BridgePost"):
			_set_authored_material(original, _materials.wood)
		elif owner_name.begins_with("BridgeCue"):
			_set_authored_material(original, _materials.leaf)
		elif owner_name == "TrenchBottom":
			_set_authored_material(original, _materials.stone)
	var landscape: Node3D = _root(world, "ProductionLandscape")
	# Recessed cores close the seams; only the replaced wall Mesh is hidden.
	# The low toes still mark the exact collision boundary at x = +/-9.8.
	for floor_name in ["StartingGarden", "StoneGarden", "SourceGarden"]:
		var floor_owner: Node3D = world.get_node(floor_name)
		var floor_mesh: MeshInstance3D = floor_owner.get_node("Mesh")
		var bounds: AABB = (floor_owner.transform * floor_mesh.transform) * floor_mesh.mesh.get_aabb()
		var top: float = bounds.end.y
		var count: int = int(ceil(bounds.size.z / 2.3))
		for side in [-1.0, 1.0]:
			var wall_owner: Node3D = world.get_node(floor_name + ("West" if side < 0.0 else "East"))
			var wall_mesh: MeshInstance3D = wall_owner.get_node("Mesh")
			var wall: AABB = (wall_owner.transform * wall_mesh.transform) * wall_mesh.mesh.get_aabb()
			var inner: float = wall.end.x if side < 0.0 else wall.position.x
			_box(landscape, Vector3(0.24, 0.22, wall.size.z),
				Vector3(inner + side * 0.12, top + 0.11, wall.get_center().z), "stone")
			_box(landscape, Vector3(0.30, 1.05, wall.size.z),
				Vector3(inner + side * 0.90, top + 0.525, wall.get_center().z), "stone")
			for index in range(count):
				var z: float = bounds.position.z + (index + 0.5) * bounds.size.z / count
				var rock: Node3D = _model(landscape, "rock",
					Vector3(2.75, 1.85, bounds.size.z / count + 0.40),
					Vector3(0, top - 0.04, z),
					"edge_%s_%s_%02d" % [floor_name, int(side), index], float(index % 4) * 90.0 + side * 11.0)
				var fitted: AABB = _models.hierarchy_bounds(rock)
				rock.position.x = inner - (fitted.end.x if side < 0.0 else fitted.position.x)
				# Close each exposed end without extending rocks into the trench.
				rock.position.z = clampf(z, wall.position.z - fitted.position.z, wall.end.z - fitted.end.z)
				rock.set_meta("assembly", "edge-assemblies")
			for z in [wall.position.z + 0.09, wall.end.z - 0.09]:
				_box(landscape, Vector3(1.05, 1.05, 0.18),
					Vector3(inner + side * 0.525, top + 0.525, z), "stone")
			_hide(wall_mesh)
	# Face the void instead of burying the bank in the opaque floor side.
	# Tops remain visibly below the tread; at least 4.2m of trench stays open.
	for bank in [0.0, -6.0]:
		var toward_gap: float = -1.0 if bank == 0.0 else 1.0
		for index in range(9):
			var rock: Node3D = _model(landscape, "rock", Vector3(2.75, 3.0, 2.6),
				Vector3(-8.8 + index * 2.2, 0, bank),
				"cliff_%s_%02d" % [int(bank), index], float(index % 4) * 90.0)
			var fitted: AABB = _models.hierarchy_bounds(rock)
			rock.position.y = -0.35 - fitted.end.y
			rock.position.z = bank + toward_gap * 0.90 - (fitted.position.z if toward_gap < 0.0 else fitted.end.z)
	# No overhead geometry crosses the original four-metre gate opening.
	for side in [-1.0, 1.0]:
		var wall_owner: Node3D = world.get_node("GateWallWest" if side < 0.0 else "GateWallEast")
		var wall_mesh: MeshInstance3D = wall_owner.get_node("Mesh")
		var wall: AABB = (wall_owner.transform * wall_mesh.transform) * wall_mesh.mesh.get_aabb()
		var inner: float = wall.end.x if side < 0.0 else wall.position.x
		_box(landscape, Vector3(wall.size.x, 2.80, 0.22),
			Vector3(wall.get_center().x, 1.40, wall.position.z + 0.22), "stone")
		_box(landscape, Vector3(wall.size.x, 0.18, wall.size.z),
			Vector3(wall.get_center().x, 0.09, wall.get_center().z), "stone")
		# Exact jamb returns cover the core ends and identify the opening.
		_box(landscape, Vector3(0.18, wall.size.y, wall.size.z),
			Vector3(inner + side * 0.09, wall.get_center().y, wall.get_center().z), "stone")
		_box(landscape, Vector3(0.90, 2.80, 0.22),
			Vector3(side * 10.25, 1.40, wall.position.z + 0.22), "stone")
		for index in range(5):
			for course in range(3):
				var rock: Node3D = _model(landscape, "rock", Vector3(2.15, 1.20, 2.10),
					Vector3.ZERO,
					"gate_cheek_%s_%s_%s" % [int(side), index, course], float((index + course) % 4) * 90.0)
				var fitted: AABB = _models.hierarchy_bounds(rock)
				var x: float = inner + side * ((index + 0.5) * 7.8 / 5.0 + (0.13 if course == 1 else 0.0))
				var low_x: float = -9.8 if side < 0.0 else inner
				var high_x: float = inner if side < 0.0 else 9.8
				rock.position.x = clampf(x, low_x - fitted.position.x, high_x - fitted.end.x)
				rock.position.y = wall.position.y + float(course) * (wall.size.y - fitted.size.y) * 0.5 - fitted.position.y
				# Rear faces embed in the recessed core; most of each stone is
				# forward of the former wall, clear of RootLock and its approach.
				rock.position.z = wall.position.z + 0.10 - fitted.position.z
		_hide(wall_mesh)
	# Canopies stay outside x = +/-10 and flank the ordinary forward route.
	for entry in [Vector3(-12.5, 0, -8.5), Vector3(12.5, 0, -22.5)]:
		_model(landscape, "tree", Vector3(4.6, 6.2, 4.6), entry,
			"tree_%s" % int(entry.x), 25.0 if entry.x < 0 else -35.0)
	for boundary_name in ["SouthBoundary", "NorthBoundary"]:
		var owner: Node3D = world.get_node(boundary_name)
		var original: MeshInstance3D = owner.get_node("Mesh")
		var wall: AABB = (owner.transform * original.transform) * original.mesh.get_aabb()
		var side: float = 1.0 if boundary_name == "SouthBoundary" else -1.0
		var inner: float = wall.position.z if side > 0.0 else wall.end.z
		_box(landscape, Vector3(wall.size.x, 0.22, 0.24),
			Vector3(0, 0.11, inner + side * 0.12), "stone")
		_box(landscape, Vector3(wall.size.x, 1.05, 0.30),
			Vector3(0, 0.525, inner + side * 0.90), "stone")
		for side_x in [-1.0, 1.0]:
			_box(landscape, Vector3(1.10, 1.05, 1.10),
				Vector3(side_x * (wall.size.x * 0.5 + 0.35), 0.525, inner + side * 0.70), "stone")
		for index in range(9):
			var rock: Node3D = _model(landscape, "rock", Vector3(2.65, 1.85, 2.75),
				Vector3(-8.8 + index * 2.2, -0.04, 0),
				"boundary_%s_%s" % [boundary_name, index], float(index % 4) * 90.0 + 9.0)
			var fitted: AABB = _models.hierarchy_bounds(rock)
			rock.position.z = inner - (fitted.position.z if side > 0.0 else fitted.end.z)
		_hide(original)

func _build_mechanisms() -> void:
	for stone_owner in game.get_node("Mechanisms/Gate/Stones").get_children():
		var original: MeshInstance3D = stone_owner.get_node("Mesh")
		var bounds: AABB = original.transform * original.mesh.get_aabb()
		var layer: Node3D = _root(stone_owner, "ProductionRubble")
		_model(layer, "rock", bounds.size, Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z),
			"rubble_" + str(stone_owner.name))
		_hide(original)
	var source: Node3D = game.get_node("Mechanisms/Altar/SourceStone")
	var source_mesh: MeshInstance3D = source.get_node("Mesh")
	var source_bounds: AABB = source_mesh.transform * source_mesh.mesh.get_aabb()
	_model(_root(source, "ProductionStele"), "stele", source_bounds.size,
		Vector3(0, source_bounds.position.y, 0), "source_stone")
	_hide(source_mesh)
	_set_authored_material(game.get_node("Mechanisms/Altar/Base/Mesh"), _materials.stone)
	var altar_trim: Node3D = _root(game.get_node("Mechanisms/Altar"), "ProductionPlinthTrim")
	for side in [-1.0, 1.0]:
		_box(altar_trim, Vector3(2.2, 0.045, 0.065), Vector3(0, 0.39, side * 1.06), "root")
		_box(altar_trim, Vector3(0.065, 0.045, 2.2), Vector3(side * 1.06, 0.39, 0), "root")
	var bridge: Node3D = game.get_node("Mechanisms/Bridge")
	var body: Node3D = bridge.get_node("Body")
	var shape_node: CollisionShape3D = body.get_node("CollisionShape3D")
	var box_shape: BoxShape3D = shape_node.shape
	var support: AABB = (body.transform * shape_node.transform) * AABB(-box_shape.size * 0.5, box_shape.size)
	var top: float = support.end.y
	_bridge_art = _root(bridge, "ProductionBridge")
	_deck = _box(_bridge_art, Vector3(support.size.x, 0.06, support.size.z),
		Vector3(support.get_center().x, top - 0.14, support.get_center().z), "vine")
	_deck.name = "ContinuousDeck"
	# Long source axis follows the crossing. Keep a thin, exact tread and
	# expose generated woven modules along its sides, outside the standing area.
	# The existing sync scales this one root using the original plank tween.
	_bridge_structure = _root(_bridge_art, "GeneratedBridgeStructure")
	var bridge_body: Node3D = _model(_bridge_structure, "bridge", Vector3(support.size.x, 4.0, support.size.z),
		Vector3(support.get_center().x, 0, support.get_center().z), "bridge_structure", 90.0)
	bridge_body.position.y = top - _models.hierarchy_bounds(bridge_body).size.y * float(_models.sources.bridge.support_surface_fraction)
	# Readable continuous vine support at the exact collision height, including
	# end gaps left by a proportionally fitted generated bridge.
	for index in range(13):
		var x: float = lerpf(support.position.x + 0.06, support.end.x - 0.06, float(index) / 12.0)
		_tube(_bridge_structure, Vector3(x, top - 0.015, support.position.z),
			Vector3(x, top - 0.015, support.end.z), 0.035, "vine")
	var side_envelope := Vector3(0.90, 2.0, 1.60)
	var oriented: AABB = _models.hierarchy_bounds(_models.templates.bridge,
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))
	var factor: float = minf(side_envelope.x / oriented.size.x,
		minf(side_envelope.y / oriented.size.y, side_envelope.z / oriented.size.z)) * float(_models.sources.bridge.size_fraction)
	var side_count: int = int(ceil(support.size.z / (oriented.size.z * factor * 0.88)))
	var spacing: float = support.size.z / side_count
	for side in [-1.0, 1.0]:
		var edge: float = support.position.x if side < 0.0 else support.end.x
		for index in range(side_count):
			var woven: Node3D = _model(_bridge_structure, "bridge", side_envelope, Vector3.ZERO,
				"bridge_weave_%s_%02d" % [int(side), index], 90.0 if index % 2 == 0 else 270.0)
			var fitted: AABB = _models.hierarchy_bounds(woven)
			woven.position.x = edge - (fitted.end.x if side < 0.0 else fitted.position.x)
			woven.position.y = top - 0.055 - fitted.position.y
			woven.position.z = clampf(support.position.z + (index + 0.5) * spacing,
				support.position.z - fitted.position.z, support.end.z - fitted.end.z)
	for plank in bridge.get_node("Planks").get_children():
		_hide(plank.get_node("Mesh"))
		# Children of each exact original plank pivot inherit its original tween.
		var cap: Node3D = _root(plank, "ProductionPlank")
		# Narrow flush bindings replace the opaque green caps.
		_box(cap, Vector3(support.size.x, 0.016, 0.045), Vector3(0, top - plank.position.y - 0.008, 0), "root")
	for rail_name in ["VineRailLeft", "VineRailRight"]:
		_hide(bridge.get_node(rail_name + "/Mesh"))
	for side in [-1.0, 1.0]:
		var x: float = side * (support.size.x * 0.5 - 0.075)
		_tube(_bridge_structure, Vector3(side * support.size.x * 0.5, top - 0.025, support.position.z),
			Vector3(side * support.size.x * 0.5, top - 0.025, support.end.z), 0.045, "wood")
		# Landing collars meet the exact support endpoints; remain on its edges.
		for z in [support.position.z, support.end.z]:
			_box(_bridge_art, Vector3(0.20, 0.12, 0.28), Vector3(x, top + 0.02, z), "root")

func _build_player_and_pickup() -> void:
	var tool: Node3D = game.get_node("Player/Body/Tool")
	_model(_root(tool, "ProductionWateringCan"), "watering_can", Vector3(0.55, 0.48, 0.50),
		Vector3(0, -0.24, 0), "watering_can")
	_hide(tool.get_node("Mesh"))
	_set_authored_material(game.get_node("Player/Body/Capsule"), _materials.cream)
	var pickup: Node3D = game.get_node("Pickups/RootSeeds")
	_set_authored_material(pickup.get_node("Crate/Mesh"), _materials.wood)
	_hide(pickup.get_node("SeedMark/Mesh"))
	var layer: Node3D = _root(pickup, "ProductionSeedCache")
	_model(layer, "root_seed", Vector3(0.32, 0.32, 0.32), Vector3(0, 0.81, 0), "cache_seed")
	for side in [-1.0, 1.0]:
		_box(layer, Vector3(0.05, 0.82, 0.92), Vector3(side * 0.38, 0.41, 0), "root")

func _build_plot(plot: Node3D) -> void:
	var id: String = str(plot.get("plot_id"))
	var root: Node3D = _root(plot, "ProductionPlot")
	var soil := _model(root, "soil", Vector3(2.4, 0.30, 2.4), Vector3.ZERO, "soil_" + id)
	var ground_top: float = maxf(0.065, _models.hierarchy_bounds(soil).size.y * float(_models.sources.soil.support_surface_fraction))
	# The exact bed footprint and rim close any gaps left by uniform fitting.
	_box(root, Vector3(2.4, 0.06, 2.4), Vector3(0, 0.03, 0), "soil")
	for side in [-1.0, 1.0]:
		_box(root, Vector3(2.4, 0.14, 0.09), Vector3(0, 0.19, side * 1.155), "rim")
		_box(root, Vector3(0.09, 0.14, 2.4), Vector3(side * 1.155, 0.19, 0), "rim")
	var hard := Node3D.new()
	hard.name = "HardClods"
	root.add_child(hard)
	_box(hard, Vector3(2.1, 0.025, 2.1), Vector3(0, ground_top + 0.0125, 0), "soil")
	for index in range(3):
		_model(hard, "rock", Vector3(0.27, 0.16, 0.27),
			Vector3(-0.65 + index * 0.6, ground_top + 0.025, 0.22 * (index % 2)), "clod_%s_%s" % [id, index])
	var furrows := Node3D.new()
	furrows.name = "CultivatedFurrows"
	root.add_child(furrows)
	for index in range(4):
		_box(furrows, Vector3(0.045, 0.015, 1.8),
			Vector3(-0.75 + index * 0.5, ground_top + 0.005, 0), "soil")
	var crop := Node3D.new()
	crop.name = "GeneratedCrop"
	root.add_child(crop)
	_plots[id] = {
		"owner": plot, "root": root, "hard": hard, "furrows": furrows, "soil_model":soil,
		"crop_root": crop, "ground_top": ground_top, "signature": "",
		"visual_stage": "none", "model": "", "model_node": null,
	}
	_hide(plot.get_node("Soil"))
	_hide(plot.get_node("CropVisual"))
	for child in plot.get_children():
		if str(child.name).begins_with("Rune"):
			var mesh: MeshInstance3D = child.get_node_or_null("Mesh")
			if mesh != null:
				_set_authored_material(mesh, _materials.vine if int(plot.get("required_crop")) == 0 else _materials.root)

func _build_revival() -> void:
	var revival: Node3D = game.get_node("Revival")
	# Keep the original reveal owner and its visibility entirely gameplay-owned.
	var existing: Array[Node] = revival.get_children()
	var layer: Node3D = _root(revival, "ProductionRevival")
	for child in existing:
		if str(child.name).begins_with("Patch"):
			var at: Vector3 = child.position
			for index in range(5):
				_grass(layer, at + Vector3((index - 2) * 0.38, 0, sin(float(index) * 2.0) * 0.45), 0.55)
		if child is Node3D:
			_hide(child)

func _process(_delta: float) -> void:
	synchronize_state()

func synchronize_state() -> void:
	if not _sync_enabled:
		return
	for id in PLOT_IDS:
		var entry: Dictionary = _plots[id]
		var plot: Node3D = entry.owner
		if not is_instance_valid(entry.root) or entry.root.is_queued_for_deletion() or entry.root.get_parent() != plot:
			_build_plot(plot)
			entry = _plots[id]
		# refresh() may replace the original meshes on any plot, even if this
		# plot's stage did not change. Hide its container on every sync.
		var original_crop: Node3D = plot.get_node_or_null("CropVisual")
		if original_crop != null:
			_hide(original_crop)
		_hide(plot.get_node("Soil"))
		var logical: int = int(plot.get("stage"))
		var crop: int = int(plot.get("crop"))
		var growth: float = float(plot.get("growth"))
		var visual_stage: String = "none"
		if logical == 2:
			visual_stage = "seed"
		elif logical == 3:
			visual_stage = "leafy" if growth >= 1.5 else "sprout"
		elif logical == 4:
			visual_stage = "mature"
		entry.hard.visible = logical == 0
		entry.soil_model.visible = true
		entry.furrows.visible = logical >= 1
		var model_key: String = ""
		if visual_stage != "none" and crop in [0, 1]:
			model_key = ("vine_" if crop == 0 else "root_") + visual_stage
		var signature: String = "%d:%d:%s" % [logical, crop, visual_stage]
		var lost_model: bool = model_key != "" and (not is_instance_valid(entry.model_node) or entry.model_node.is_queued_for_deletion() or entry.model_node.get_parent() != entry.crop_root)
		if entry.signature == signature and not lost_model:
			continue
		for child in entry.crop_root.get_children():
			entry.crop_root.remove_child(child)
			child.queue_free()
		entry.model_node = null
		_models.normalization_bounds.erase("crop_" + str(id))
		entry.signature = signature
		entry.visual_stage = visual_stage
		entry.model = model_key
		if model_key != "":
			var sizes: Dictionary = {
				"seed": Vector3(0.38, 0.22, 0.38),
				"sprout": Vector3(0.75, 0.52, 0.75),
				"leafy": Vector3(1.4, 0.95, 1.4),
				"mature": Vector3(2.1, 1.68 if crop == 0 else 1.18, 2.1),
			}
			entry.model_node = _model(entry.crop_root, model_key, sizes[visual_stage],
				Vector3(0, entry.ground_top, 0), "crop_" + str(id))
	# Read the original tween; no new clocks, timers or tweens are introduced.
	if is_instance_valid(_deck):
		var plank: Node3D = game.get_node("Mechanisms/Bridge/Planks/Plank00")
		_deck.scale.y = plank.scale.y
		_bridge_structure.scale.y = plank.scale.y

func get_report() -> Dictionary:
	var current_ids: Array[int] = []
	if is_instance_valid(game):
		_colliders(game, current_ids)
	collider_after = current_ids.size()
	var active_stages: Dictionary = {}
	for id in _plots:
		var entry: Dictionary = _plots[id]
		var logical: int = int(entry.owner.get("stage"))
		active_stages[id] = {
			"logical": LOGICAL_STAGES[logical] if logical in range(5) else "invalid",
			"crop": entry.owner.get("crop"), "growth_hours": entry.owner.get("growth"),
			"visual": entry.visual_stage, "model": entry.model,
		}
	var metrics: Dictionary = {
		"generated_instances": 0, "generated_mesh_instances": 0, "generated_triangles": 0,
		"visible_generated_triangles": 0, "procedural_mesh_instances": 0, "procedural_triangles": 0,
	}
	for root in _owned_roots:
		if is_instance_valid(root) and not root.is_queued_for_deletion():
			_count_visuals(root, metrics)
	var source_triangles: int = 0
	var source_materials: int = 0
	for source in _models.sources.values():
		source_triangles += int(source.triangles)
		source_materials += int(source.material_count)
	var missing: Array[String] = []
	for key in REQUIRED_MODELS:
		if not _models.sources.has(key):
			missing.append(key)
	return {
		"style": style_id, "manifest_path": manifest_path, "manifest_sha256": _manifest_hash,
		"assembled": assembled, "assembly_errors": assembly_errors.duplicate(),
		"status": "assembled_pending_native_review" if assembled else ("blocked" if _started else "waiting_ready"),
		"final_accepted": false, "required_model_count": 14,
		"loaded_model_count": _models.sources.size(), "missing_models": missing,
		"sources": _models.sources.duplicate(true),
		"source_triangles": source_triangles, "source_materials": source_materials,
		"metrics": metrics, "collider_before": collider_before, "collider_after": collider_after,
		"collider_inventory_unchanged": _collider_ids == current_ids,
		"active_visual_stages": active_stages,
		"normalization_bounds": _models.normalization_bounds.duplicate(true),
		"material_policy": "GLTF colour/data textures preserved; explicit two-sided foliage adjustment logged per source; lighting unmodified.",
		"verification": "Runtime assembly is not native gameplay, material, camera or aesthetic acceptance.",
	}

func _root(parent: Node3D, label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	parent.add_child(node)
	_owned_roots.append(node)
	return node

func _model(parent: Node3D, key: String, size: Vector3, at: Vector3, id: String, yaw: float = 0.0) -> Node3D:
	var node: Node3D = _models.instantiate_model(key, size, id, yaw)
	if node == null:
		_error("Unable to instantiate mandatory source " + key + " at " + id)
		return null
	parent.add_child(node)
	node.position = at
	return node

func _box(parent: Node3D, size: Vector3, at: Vector3, material_key: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = _materials[material_key]
	parent.add_child(node)
	return node

func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, material_key: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.85
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 7
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = (a + b) * 0.5
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	node.material_override = _materials[material_key]
	parent.add_child(node)
	return node

func _grass(parent: Node3D, at: Vector3, height: float) -> void:
	for index in range(3):
		var angle: float = float(index) * TAU / 3.0
		var end: Vector3 = at + Vector3(cos(angle) * 0.18, height * (0.70 + index * 0.12), sin(angle) * 0.18)
		_tube(parent, at, end, 0.025, "leaf")

func _hide(node: Node3D) -> void:
	if not _hidden.has(node):
		_hidden[node] = node.visible
	node.visible = false

func _set_authored_material(mesh: MeshInstance3D, mat: Material) -> void:
	if not _material_changes.has(mesh):
		_material_changes[mesh] = mesh.material_override
	mesh.material_override = mat

func _colliders(node: Node, ids: Array[int]) -> void:
	if node == game:
		ids.clear()
	if node is CollisionShape3D or node is CollisionPolygon3D:
		ids.append(node.get_instance_id())
	for child in node.get_children():
		_colliders(child, ids)

func _count_visuals(node: Node, metrics: Dictionary) -> void:
	if node.has_meta("garden_model"):
		var source: Dictionary = _models.sources[node.get_meta("garden_model")]
		metrics.generated_instances += 1
		metrics.generated_mesh_instances += int(source.mesh_instances)
		metrics.generated_triangles += int(source.triangles)
		if node.is_visible_in_tree():
			metrics.visible_generated_triangles += int(source.triangles)
		return
	if node is MeshInstance3D and node.mesh != null:
		metrics.procedural_mesh_instances += 1
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: int = arrays[Mesh.ARRAY_VERTEX].size() if arrays[Mesh.ARRAY_VERTEX] != null else 0
			var indices: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0
			metrics.procedural_triangles += int((indices if indices > 0 else vertices) / 3)
	for child in node.get_children():
		_count_visuals(child, metrics)

func _error(message: String) -> void:
	if not assembly_errors.has(message):
		assembly_errors.append(message)
		push_error("GardenArt: " + message)
	assembled = false

func _remove_visual_layer() -> void:
	_sync_enabled = false
	assembled = false
	for node in _hidden:
		if is_instance_valid(node):
			node.visible = _hidden[node]
	for mesh in _material_changes:
		if is_instance_valid(mesh):
			mesh.material_override = _material_changes[mesh]
	for node in _owned_roots:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	_owned_roots.clear()
	_hidden.clear()
	_material_changes.clear()
	_plots.clear()

func _exit_tree() -> void:
	_remove_visual_layer()
	_models.clear()
