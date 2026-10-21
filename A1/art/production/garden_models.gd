extends RefCounted
## Static GLB visual adapter. Never adds the imported scene to the gameplay tree.
## Runtime GLTF decoding avoids executing scripts from editor import overrides.

var errors: Array[String] = []
var sources: Dictionary = {}
var templates: Dictionary = {}
var normalization_bounds: Dictionary = {}
var instances_created: int = 0

func clear() -> void:
	for template in templates.values():
		template.free()
	templates.clear()
	sources.clear()
	normalization_bounds.clear()
	errors.clear()
	instances_created = 0

func load_model(key: String, entry: Dictionary) -> bool:
	var path: String = str(entry.get("path", ""))
	var expected_hash: String = str(entry.get("sha256", "")).to_lower()
	if not path.begins_with("res://") or path.get_extension().to_lower() != "glb" or ".." in path:
		return _fail(key, "requires an immutable project-local res://*.glb path")
	if expected_hash.length() != 64 or not expected_hash.is_valid_hex_number(false):
		return _fail(key, "requires a 64-digit SHA-256")
	if not FileAccess.file_exists(path):
		return _fail(key, "missing source: " + path)
	var actual_hash: String = FileAccess.get_sha256(path)
	if actual_hash != expected_hash:
		return _fail(key, "source SHA-256 mismatch: " + path)
	var rotation_value: Variant = entry.get("rotation_degrees", [0, 0, 0])
	if not _valid_vector(rotation_value):
		return _fail(key, "rotation_degrees must contain three finite numbers")
	var settings: Variant = entry.get("normalization", {})
	if not settings is Dictionary:
		return _fail(key, "normalization must be an object")
	var size_fraction: float = float(settings.get("size_fraction", 1.0))
	if not is_finite(size_fraction) or size_fraction <= 0.0 or size_fraction > 1.0:
		return _fail(key, "normalization.size_fraction must be in (0, 1]")
	# GLB has no script attachment channel. No .tscn, custom import scene or
	# editor post-import script is instantiated by this adapter.
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result: int = document.append_from_file(path, state)
	if result != OK:
		return _fail(key, "GLTF decode failed (%s): %s" % [result, path])
	var imported: Node = document.generate_scene(state)
	if imported == null:
		return _fail(key, "GLTF generated no scene")
	var clean := Node3D.new()
	clean.name = key
	var stats: Dictionary = {
		"path": path, "sha256": actual_hash, "bytes": FileAccess.get_file_as_bytes(path).size(),
		"loader": "GLTFDocument runtime, default material decoding",
		"mesh_instances": 0, "surfaces": 0, "triangles": 0, "vertices": 0,
		"materials": [], "textures": [], "discarded_nodes": {},
		"size_fraction": size_fraction, "rotation_degrees": rotation_value,
		"foliage_double_sided": bool(entry.get("foliage_double_sided", false)),
		"material_adjustments": [],
		"support_surface_fraction": clampf(float(entry.get("support_surface_fraction", 1.0)), 0.0, 1.0),
	}
	var rotation_vector := Vector3(float(rotation_value[0]), float(rotation_value[1]), float(rotation_value[2]))
	var orientation := Transform3D(Basis.from_euler(rotation_vector * (PI / 180.0)), Vector3.ZERO)
	_copy_visuals(imported, clean, orientation, stats, key)
	imported.free()
	if int(stats.mesh_instances) == 0 or int(stats.triangles) == 0:
		clean.free()
		return _fail(key, "no supported static triangle meshes")
	var bounds: AABB = hierarchy_bounds(clean)
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0.00001 or bounds.size.y <= 0.00001 or bounds.size.z <= 0.00001:
		clean.free()
		return _fail(key, "empty, flat or non-finite full hierarchy bounds")
	if errors.any(func(message: String) -> bool: return message.begins_with(key + ":")):
		clean.free()
		return false
	stats["source_bounds"] = bounds_report(bounds)
	stats["material_count"] = stats.materials.size()
	stats["texture_count"] = stats.textures.size()
	templates[key] = clean
	sources[key] = stats
	return true

func _copy_visuals(node: Node, clean: Node3D, relative: Transform3D, stats: Dictionary, key: String, ancestor_visible: bool = true) -> void:
	var full: Transform3D = relative
	var source_visible: bool = ancestor_visible
	if node is Node3D:
		full = relative * node.transform
		source_visible = ancestor_visible and node.visible
	if node.get_script() != null:
		_count_discarded(stats, "script")
	# Only whitelisted static meshes are copied. Everything else, including
	# animation players, bodies, shapes, audio, lights and cameras, is discarded.
	# Children still inherit every ancestor transform, including collision owners.
	if node is MeshInstance3D and node.mesh != null:
		if node.skin != null or node.mesh.get_blend_shape_count() > 0:
			_fail(key, "rigged/blend-shape mesh requires a dedicated adapter")
		else:
			var visual := MeshInstance3D.new()
			visual.name = "Visual_%03d" % int(stats.mesh_instances)
			visual.mesh = node.mesh
			visual.transform = full
			visual.material_override = node.material_override
			visual.material_overlay = node.material_overlay
			visual.cast_shadow = node.cast_shadow
			visual.visible = source_visible
			for surface in range(node.mesh.get_surface_count()):
				visual.set_surface_override_material(surface, node.get_surface_override_material(surface))
				var original_material: Material = visual.get_active_material(surface)
				if stats.foliage_double_sided and original_material is BaseMaterial3D:
					var adjusted: BaseMaterial3D = original_material.duplicate(false)
					adjusted.cull_mode = BaseMaterial3D.CULL_DISABLED
					adjusted.metallic_specular = minf(adjusted.metallic_specular, 0.20)
					if visual.material_override != null:
						visual.material_override = adjusted
					else:
						visual.set_surface_override_material(surface, adjusted)
					stats.material_adjustments.append({"surface":surface,"kind":"two_sided_foliage",
						"original_cull":original_material.cull_mode,"runtime_cull":adjusted.cull_mode,
						"original_specular":original_material.metallic_specular,
						"runtime_specular":adjusted.metallic_specular,
						"textures_preserved":true})
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				var vertices: int = arrays[Mesh.ARRAY_VERTEX].size() if arrays[Mesh.ARRAY_VERTEX] != null else 0
				var indices: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0
				var elements: int = indices if indices > 0 else vertices
				var primitive: int = node.mesh.surface_get_primitive_type(surface)
				if primitive == Mesh.PRIMITIVE_TRIANGLES:
					stats.triangles += int(elements / 3)
				elif primitive == Mesh.PRIMITIVE_TRIANGLE_STRIP:
					stats.triangles += maxi(0, elements - 2)
				else:
					_fail(key, "non-triangle surface requires a dedicated adapter")
				stats.vertices += vertices
				stats.surfaces += 1
				_record_material(visual.get_active_material(surface), stats)
			_record_material(visual.material_overlay, stats)
			clean.add_child(visual)
			stats.mesh_instances += 1
	elif node.get_class() != "Node3D" and node.get_class() != "Node":
		_count_discarded(stats, node.get_class())
		if node is MultiMeshInstance3D or node is Skeleton3D:
			_fail(key, "unsupported generated geometry: " + node.get_class())
	for child in node.get_children():
		_copy_visuals(child, clean, full, stats, key, source_visible)

func instantiate_model(key: String, envelope: Vector3, instance_id: String, yaw_degrees: float = 0.0) -> Node3D:
	if not templates.has(key):
		return null
	var template: Node3D = templates[key]
	var orientation := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), Vector3.ZERO)
	var bounds: AABB = hierarchy_bounds(template, orientation)
	var factor: float = minf(envelope.x / bounds.size.x, minf(envelope.y / bounds.size.y, envelope.z / bounds.size.z))
	factor *= float(sources[key].size_fraction)
	var pivot := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var fit := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * factor), -pivot * factor)
	var instance := Node3D.new()
	instance.name = instance_id.validate_node_name()
	instance.set_meta("garden_model", key)
	instance.set_meta("source_path", sources[key].path)
	for mesh_node in template.get_children():
		var visual := MeshInstance3D.new()
		visual.name = mesh_node.name
		visual.mesh = mesh_node.mesh
		visual.transform = fit * orientation * mesh_node.transform
		visual.material_override = mesh_node.material_override
		visual.material_overlay = mesh_node.material_overlay
		visual.cast_shadow = mesh_node.cast_shadow
		visual.visible = mesh_node.visible
		for surface in range(visual.mesh.get_surface_count()):
			visual.set_surface_override_material(surface, mesh_node.get_surface_override_material(surface))
		instance.add_child(visual)
	normalization_bounds[instance_id] = {
		"model": key, "source_path": sources[key].path,
		"oriented_source": bounds_report(bounds), "envelope": vector_report(envelope),
		"uniform_scale": factor, "pivot": vector_report(pivot),
		"local_result": bounds_report(hierarchy_bounds(instance)),
	}
	instances_created += 1
	return instance

func hierarchy_bounds(node: Node3D, relative: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var initialized: bool = false
	# Sanitized templates are deliberately flat; transforms already contain the
	# complete source hierarchy and root transform, not only each mesh's scale.
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var bounds: AABB = (relative * child.transform) * child.mesh.get_aabb()
			result = result.merge(bounds) if initialized else bounds
			initialized = true
	return result

func _record_material(mat: Material, stats: Dictionary) -> void:
	if mat == null:
		return
	var identity: int = mat.get_instance_id()
	for existing in stats.materials:
		if existing.instance_id == identity:
			return
	var record: Dictionary = {"instance_id": identity, "class": mat.get_class(), "resource_path": mat.resource_path}
	if mat is BaseMaterial3D:
		record["albedo"] = [mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, mat.albedo_color.a]
		record["roughness"] = mat.roughness
		record["metallic"] = mat.metallic
		record["specular"] = mat.metallic_specular
		record["transparency"] = mat.transparency
		record["cull_mode"] = mat.cull_mode
		record["emission_enabled"] = mat.emission_enabled
		for slot in range(BaseMaterial3D.TEXTURE_MAX):
			var texture: Texture2D = mat.get_texture(slot)
			if texture != null:
				var texture_id: int = texture.get_instance_id()
				if not stats.textures.has(texture_id):
					stats.textures.append(texture_id)
	stats.materials.append(record)

func _count_discarded(stats: Dictionary, kind: String) -> void:
	stats.discarded_nodes[kind] = int(stats.discarded_nodes.get(kind, 0)) + 1

func _valid_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)):
			return false
	return true

func _fail(key: String, message: String) -> bool:
	errors.append(key + ": " + message)
	return false

func bounds_report(bounds: AABB) -> Dictionary:
	return {"position": vector_report(bounds.position), "size": vector_report(bounds.size)}

func vector_report(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
