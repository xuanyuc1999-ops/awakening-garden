extends Node
## Dedicated skinned visual adapter. The original CharacterBody remains authoritative.
@export var manifest_path: String = "res://art/farmer-r1/farmer.json"
var game: Node
var player: CharacterBody3D
var farmer: Node3D
var animator: AnimationPlayer
var skeleton: Skeleton3D
var visual_ready = false
var errors: Array[String] = []
var source_sha256 = ""
var bounds_height = 0.0
var skeleton_bones = 0
var animation_count = 0
var idle_clip = ""
var walk_clip = ""
var played_clips: Array[String] = []
var original_collider: Dictionary = {}
var configuration: Dictionary = {}
var source_bounds: AABB
var tool: Node3D
var hand_bone = -1
var meshes = 0
var skin_meshes = 0
var normalization_scale = 1.0

func _ready() -> void:
	game = get_parent()
	player = game.get_node("Player")
	original_collider = _collider()
	process_priority = 120
	call_deferred("_assemble")

func _collider() -> Dictionary:
	var c: CollisionShape3D = player.get_node("CollisionShape3D")
	var s: CapsuleShape3D = c.shape
	return {"node": c.get_instance_id(), "shape": s.get_instance_id(),
		"transform": c.transform, "radius": s.radius, "height": s.height,
		"disabled": c.disabled, "layer": player.collision_layer,
		"mask": player.collision_mask, "floor_snap": player.floor_snap_length}

func _fail(message: String) -> void:
	errors.append(message)
	push_error("Farmer visual: " + message)

func _assemble() -> void:
	# Both legacy visual layers create their dressing through deferred calls.
	await get_tree().process_frame
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary:
		_fail("Missing or invalid manifest")
		return
	configuration = data
	var path = str(configuration.get("path", ""))
	if not path.begins_with("res://art/farmer-r1/assets/") or path.get_extension() != "glb":
		_fail("Model must be a local GLB")
		return
	source_sha256 = FileAccess.get_sha256(path)
	if source_sha256 != str(configuration.get("sha256", "")):
		_fail("Source hash mismatch")
		return
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	if document.append_from_file(path, state) != OK:
		_fail("GLTF decode failed")
		return
	farmer = document.generate_scene(state) as Node3D
	if farmer == null or not _inspect(farmer):
		if farmer != null: farmer.free()
		_fail("Unsupported or unsafe GLTF scene")
		return
	if skeleton == null or animator == null or skin_meshes == 0:
		farmer.free()
		_fail("Character requires a skeleton, skinned mesh and animation player")
		return
	skeleton_bones = skeleton.get_bone_count()
	idle_clip = str(configuration.get("idle_clip", ""))
	walk_clip = str(configuration.get("walk_clip", ""))
	if idle_clip == walk_clip or not animator.has_animation(idle_clip) or not animator.has_animation(walk_clip):
		farmer.free()
		_fail("Actual idle/walk clip mapping missing")
		return
	for clip in animator.get_animation_list():
		if clip != "RESET" and animator.get_animation(clip).get_track_count() > 0:
			animation_count += 1
	for clip in [idle_clip, walk_clip]:
		animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var body: Node3D = player.get_node("Body")
	var orientation = Node3D.new()
	orientation.name = "FarmerOrientation"
	body.add_child(orientation)
	orientation.rotation.y = deg_to_rad(float(configuration.get("yaw_degrees", 180.0)))
	farmer.name = "GeneratedFarmer"
	orientation.add_child(farmer)
	source_bounds = _bounds(farmer, Transform3D.IDENTITY)
	if source_bounds.size.y < 0.1 or not source_bounds.size.is_finite():
		_fail("Invalid body bounds")
		return
	bounds_height = float(configuration.get("height", 1.78))
	normalization_scale = bounds_height / source_bounds.size.y
	farmer.scale = Vector3.ONE * normalization_scale
	farmer.position = -Vector3(source_bounds.get_center().x, source_bounds.position.y, source_bounds.get_center().z) * normalization_scale
	# Hide only legacy body dressing; original physics and tool ownership survive.
	for child in body.get_children():
		if child == orientation: continue
		if child is MeshInstance3D or child.name == "Facing":
			child.visible = false
	tool = body.get_node("Tool")
	var requested_hand = str(configuration.get("right_hand_bone", ""))
	if requested_hand != "":
		hand_bone = skeleton.find_bone(requested_hand)
	visual_ready = true
	_play(idle_clip)

func _inspect(node: Node) -> bool:
	if node.get_script() != null: return false
	if node is CollisionObject3D or node is CollisionShape3D or node is Camera3D or node is Light3D:
		return false
	if not (node is Node3D or node is AnimationPlayer): return false
	if node is Skeleton3D:
		if skeleton != null: return false
		skeleton = node
	if node is AnimationPlayer:
		if animator != null: return false
		animator = node
		for clip_name in animator.get_animation_list():
			var animation: Animation = animator.get_animation(clip_name)
			for i in animation.get_track_count():
				# GLTF bone transforms and blend weights only; never method/audio tracks.
				if animation.track_get_type(i) not in [Animation.TYPE_POSITION_3D,
						Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE]:
					return false
	if node is MeshInstance3D and node.mesh != null:
		meshes += 1
		if node.skin != null: skin_meshes += 1
	for child in node.get_children():
		if not _inspect(child): return false
	return true

func _bounds(node: Node, parent_transform: Transform3D) -> AABB:
	var t = parent_transform
	if node is Node3D: t = parent_transform * node.transform
	var result = AABB()
	var populated = false
	if node is MeshInstance3D and node.mesh != null:
		result = t * node.mesh.get_aabb()
		populated = true
	for child in node.get_children():
		var b = _bounds(child, t)
		if b.size.length_squared() > 0.000001:
			result = result.merge(b) if populated else b
			populated = true
	return result

func _play(clip: String) -> void:
	if animator.current_animation != clip:
		animator.play(clip, 0.18)
		if not played_clips.has(clip): played_clips.append(clip)

func _process(_delta: float) -> void:
	if not visual_ready: return
	var speed = Vector2(player.velocity.x, player.velocity.z).length()
	var moving = game.active and speed > 0.12
	_play(walk_clip if moving else idle_clip)
	animator.speed_scale = clampf(speed / 3.6, 0.65, 1.8) if moving else 1.0
	if hand_bone >= 0 and is_instance_valid(tool):
		var wrist: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(hand_bone)
		# The watering can keeps its authored world scale and hangs below the wrist.
		tool.global_position = wrist.origin + Vector3(0, -0.10, 0)

func get_report() -> Dictionary:
	return {"ready": visual_ready, "source_sha256": source_sha256, "skeleton_count": 1 if skeleton != null else 0,
		"skeleton_bones": skeleton_bones, "animation_count": animation_count,
		"bounds_height": bounds_height, "normalization_scale": normalization_scale,
		"collider_unchanged": original_collider == _collider(), "errors": errors,
		"meshes": meshes, "skin_meshes": skin_meshes, "played_clips": played_clips,
		"current_clip": animator.current_animation if animator != null else "",
		"hand_bone": hand_bone, "front": "Player/Body local -Z",
		"source_bounds": {"position": str(source_bounds.position), "size": str(source_bounds.size)}}
