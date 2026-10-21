extends Node3D
## Environment dressing around the exact original gameplay spaces.
const Models = preload("res://art/production/garden_models.gd")
const SkyShader = preload("res://art/refinement-r3/garden_sky.gdshader")
const PropShader = preload("res://art/refinement-r3/prop_surface.gdshader")
@export var style_id: String = "A1"
@export var manifest_path: String = ""
var game: Node3D
var art: Node3D
var models = Models.new()
var visual_ready = false
var errors: Array[String] = []
var metrics: Dictionary = {"ruins":0,"cliffs":0,"flowers":0,"trees":0,"small_rocks":0}
var rng = RandomNumberGenerator.new()
var sky_material: ShaderMaterial
var labels: Array[Label3D] = []
var collider_ids: Array[int] = []
var trees: Array[Node3D] = []

func _ready() -> void:
	game = get_parent()
	process_priority = 130
	call_deferred("_build")

func _collision_inventory(node: Node, items: Array[int]) -> void:
	if node is CollisionShape3D or node is CollisionObject3D:
		items.append(node.get_instance_id())
	for child in node.get_children(): _collision_inventory(child,items)

func _build() -> void:
	await get_tree().process_frame
	art = game.get_node("_GreyboxArtLayer")
	if not art.assembled:
		errors.append("Base art not ready"); return
	_collision_inventory(game,collider_ids)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary:
		errors.append("Missing refinement manifest"); return
	for key in ["cliff","ruin","flowers","pier"]:
		if not data.models.has(key) or not models.load_model(key,data.models[key]):
			errors.append("Missing generated " + key)
	if not errors.is_empty():
		push_error("Refinement required assets missing"); return
	rng.seed = 753104 if style_id == "A1" else 753105
	game.get_node("World/ProductionLandscape").visible = false
	# Hide the prototype trench slab; deep canyon geology now supplies its backdrop.
	game.get_node("World/TrenchBottom/Mesh").visible = false
	for name in ["ChannelEdgeWest","ChannelEdgeEast"]:
		game.get_node("World/"+name+"/Mesh").visible = false
	for owner in game.get_node("World").get_children():
		if str(owner.name).begins_with("BridgeCue") and owner.has_node("Mesh"):
			owner.get_node("Mesh").visible = false
		if str(owner.name).begins_with("DiscardedTimber"):
			_dress_timber(owner)
	_boundaries()
	for name in ["BridgePostLeft","BridgePostRight"]:
		var post: Node3D=game.get_node("World/"+name)
		post.get_node("Mesh").visible=false
		_spawn("pier",Vector3(post.position.x,-.03,post.position.z),
			Vector3(.68,1.65,.68),0,"Carved"+name)
	_canyon_banks()
	_background()
	_groundcover()
	_revival_flowers()
	_reveal_bed_masonry()
	_finish_props()
	_atmosphere()
	_collect_labels(game)
	visual_ready = true

func _spawn(key: String, at: Vector3, size: Vector3, yaw: float, label: String) -> Node3D:
	var n: Node3D = models.instantiate_model(key,size,label,yaw)
	if n == null:
		errors.append("Failed instance " + label); return null
	add_child(n)
	n.position = at
	return n

func _old_model(key: String, at: Vector3, size: Vector3, yaw: float, label: String) -> Node3D:
	var n: Node3D = art._models.instantiate_model(key,size,label,yaw)
	add_child(n)
	n.position=at
	return n

func _boundaries() -> void:
	var serial=0
	for side in [-1.0,1.0]:
		for span in [Vector2(.0,18.0),Vector2(-20.0,-6.0),Vector2(-36.0,-20.0)]:
			var z=span.x
			while z < span.y-.15:
				var h=rng.randf_range(1.12,1.48)
				var n=_spawn("ruin",Vector3.ZERO,Vector3(100,h,100),
					90.0 if side < 0 else 270.0,"RuinEdge_%d"%serial)
				var b=models.hierarchy_bounds(n)
				if z+b.size.z > span.y+.1:
					var f=maxf(.25,(span.y-z)/b.size.z)
					n.scale*=f
					b=models.hierarchy_bounds(n)
				n.position.x = side*9.8 - (b.end.x if side<0 else b.position.x)
				n.position.y=-.025-rng.randf_range(0,.09)
				n.position.z=z-b.position.z
				z+=b.size.z-.07
				serial+=1
	# Broad rear masonry silhouettes frame the endpoint without a monotonous rock row.
	for end in [18.0,-36.0]:
		var x=-9.8
		while x<9.65:
			var n=_spawn("ruin",Vector3.ZERO,Vector3(100,rng.randf_range(1.1,1.45),100),
				180.0 if end>0 else 0.0,"RuinEnd_%d"%serial)
			var b=models.hierarchy_bounds(n)
			if x+b.size.x>9.8:
				n.scale*=maxf(.3,(9.8-x)/b.size.x); b=models.hierarchy_bounds(n)
			n.position=Vector3(x-b.position.x,-.03,end-(b.position.z if end>0 else b.end.z))
			x+=b.size.x-.07;serial+=1
	# Gate jambs preserve the four-metre opening. Layered masonry, not rock wallpaper.
	for side in [-1.0,1.0]:
		for course in range(2):
			var x=2.0
			while x<9.7:
				var n=_spawn("ruin",Vector3.ZERO,Vector3(100,1.55,100),
					0 if course==0 else 180,"GateRuin_%d"%serial)
				var b=models.hierarchy_bounds(n)
				if x+b.size.x>9.8:
					n.scale*=maxf(.25,(9.8-x)/b.size.x);b=models.hierarchy_bounds(n)
				n.position=Vector3(side*x-(b.position.x if side>0 else b.end.x),
					course*1.38-.03,-20.0-b.get_center().z)
				x+=b.size.x-.1;serial+=1
	metrics.ruins=serial
	# Sparse geological clusters interrupt the masonry rhythm and ground its supports.
	for side in [-1.0,1.0]:
		for z in [1.4,7.8,16.0,-8.8,-16.5,-24.5,-33.0]:
			var r=_old_model("rock",Vector3(side*rng.randf_range(8.55,9.25),-.08,z),
				Vector3.ONE*rng.randf_range(.65,1.35),rng.randf_range(0,360),"NaturalToe_%d"%int(metrics.small_rocks))
			r.rotation.z=side*rng.randf_range(-.10,.10)
			metrics.small_rocks+=1

func _canyon_banks() -> void:
	for bank in [0.0,-6.0]:
		var toward=-1.0 if bank==0.0 else 1.0
		for i in range(7):
			var n=_spawn("cliff",Vector3.ZERO,Vector3(3.8,8.5,3.8),
				float(i)*63.0+(25.0 if bank==0 else 170.0),"CanyonCliff_%s_%d"%[bank,i])
			var b=models.hierarchy_bounds(n)
			n.position=Vector3(-8.4+2.8*i,-.045-b.end.y,
				bank+toward*.58-(b.position.z if toward<0 else b.end.z))
			metrics.cliffs+=1
		# Generated masonry caps close irregular cliff/ground contacts.
		for side in [-1.0,1.0]:
			var x=2.45
			while x<9.7:
				var cap=_spawn("ruin",Vector3.ZERO,Vector3(100,.76,100),
					0 if bank==0 else 180,"BankCap_%s_%s_%s"%[bank,side,x])
				var cb=models.hierarchy_bounds(cap)
				if x+cb.size.x>9.9:
					cap.scale*=maxf(.2,(9.9-x)/cb.size.x);cb=models.hierarchy_bounds(cap)
				cap.position=Vector3(side*x-(cb.position.x if side>0 else cb.end.x),-.37,
					bank-(cb.position.z if toward<0 else cb.end.z))
				x+=cb.size.x-.04
				metrics.ruins+=1
	for side in [-1.0,1.0]:
		for z in [-33.5,-28.0,-22.5,-16.5,-11.0,2.5,8.0,14.5]:
			var n=_spawn("cliff",Vector3.ZERO,Vector3(5.6,11.0,5.6),
				rng.randf_range(0,360),"OuterCliff_%d"%int(metrics.cliffs))
			var b=models.hierarchy_bounds(n)
			n.position=Vector3(side*9.9-(b.end.x if side<0 else b.position.x),
				-.08-b.end.y,z)
			metrics.cliffs+=1

func _background() -> void:
	# Near framing trees sit beyond the physical boundary, leaving the route clear.
	var placements=[
		Vector3(-12.6,-.8,13.0),Vector3(13.2,-.6,6.0),Vector3(-13.4,-.4,-10.0),
		Vector3(13.2,-.8,-16.0),Vector3(-13.3,-.5,-29.0),Vector3(12.8,-.6,-33.0)]
	for p in placements:
		var n=_old_model("tree",p,Vector3.ONE*rng.randf_range(7.5,9.2),
			rng.randf_range(0,360),"FramingTree_%d"%int(metrics.trees))
		trees.append(n);metrics.trees+=1
	# Mid/far crags supply parallax and atmospheric layers in every orbit direction.
	for i in range(22):
		var angle=TAU*float(i)/22.0
		var radius=rng.randf_range(30,46)
		var p=Vector3(cos(angle)*radius,-rng.randf_range(12,22),-9+sin(angle)*radius*1.15)
		var h=rng.randf_range(14,27)
		var n=_spawn("cliff",p,Vector3(17,h,17),rng.randf_range(0,360),"DistantCrag_%02d"%i)
		metrics.cliffs+=1
		if style_id=="A1" or i%3==0:
			var b=models.hierarchy_bounds(n)
			var top=p+Vector3(0,b.end.y-.35,0)
			_old_model("tree",top,Vector3.ONE*rng.randf_range(5,8),rng.randf_range(0,360),"DistantTree_%02d"%i)
			metrics.trees+=1
	# The canyon descends into atmospheric sky, without a finite flat backdrop
	# whose far edge would cut a visible horizontal line through the landscape.

func _groundcover() -> void:
	for side in [-1.0,1.0]:
		for span in [Vector2(.6,17.3),Vector2(-19.1,-6.8),Vector2(-35.0,-21.2)]:
			for i in range(12):
				var z=lerpf(span.x,span.y,float(i)/11.0)+rng.randf_range(-.35,.35)
				var x=side*rng.randf_range(7.6,9.35)
				_spawn("flowers",Vector3(x,.005,z),Vector3.ONE*rng.randf_range(.72,1.18),
					rng.randf_range(0,360),"EdgeFlowers_%d"%int(metrics.flowers))
				metrics.flowers+=1
	# Small bedding accents meet the ground at corners; never occupy plant centers.
	for plot in game.get_node("Plots").get_children():
		for side in [-1.0,1.0]:
			var p=plot.position+Vector3(side*1.37,.01,1.15*side)
			_spawn("flowers",p,Vector3.ONE*.42,rng.randf_range(0,360),"BedFlowers_%d"%int(metrics.flowers))
			metrics.flowers+=1

func _revival_flowers() -> void:
	var revival: Node3D=game.get_node("Revival")
	revival.get_node("ProductionRevival").visible=false
	var original=revival.get_children()
	for patch in original:
		if not str(patch.name).begins_with("Patch"):continue
		for i in range(3):
			var at: Vector3=patch.position+Vector3((i-1)*.55,.01,sin(float(i)*2.0)*.35)
			var bloom=_spawn("flowers",at,Vector3.ONE*.95,float(i)*118.0,"RevivalFlowers_%d"%int(metrics.flowers))
			bloom.reparent(revival,true)
			metrics.flowers+=1

func _dress_timber(owner: Node3D) -> void:
	var old: MeshInstance3D=owner.get_node_or_null("Mesh")
	if old==null:return
	old.visible=false
	var binding=owner.get_node_or_null("ProductionTimberBinding")
	if binding:binding.visible=false
	# Rounded, uneven bark profiles replace exposed rectangular timber blocks.
	var wood=ShaderMaterial.new()
	wood.shader=PropShader
	wood.set_shader_parameter("base_color",Color("#725033") if style_id=="A1" else Color("#4b444c"))
	for i in range(3):
		var cylinder=CylinderMesh.new()
		cylinder.height=2.0-float(i)*.22
		cylinder.top_radius=.13+float(i)*.02
		cylinder.bottom_radius=.18+float(i)*.02
		cylinder.radial_segments=9
		var visual=MeshInstance3D.new()
		visual.mesh=cylinder;visual.material_override=wood
		owner.add_child(visual)
		visual.rotation.z=PI*.5
		visual.position=Vector3(float(i)*.12,-.05+float(i%2)*.18,float(i-1)*.24)

func _reveal_bed_masonry() -> void:
	for plot in game.get_node("Plots").get_children():
		var bed=plot.get_node("ProductionPlot")
		for child in bed.get_children():
			if child is MeshInstance3D and child.mesh is BoxMesh and is_equal_approx(child.mesh.size.y,.14):
				child.visible=false
		for child in plot.get_children():
			if not str(child.name).begins_with("Rune"):continue
			var mesh=child.get_node_or_null("Mesh")
			if mesh==null:continue
			mesh.visible=false
			for i in range(4):
				var glyph=MeshInstance3D.new()
				var ring=TorusMesh.new()
				ring.inner_radius=.085
				ring.outer_radius=.12
				ring.rings=10
				ring.ring_segments=6
				glyph.mesh=ring
				var mat=StandardMaterial3D.new()
				mat.albedo_color=Color("#8aab71") if int(plot.required_crop)==0 else Color("#bc9a62")
				mat.roughness=.95
				glyph.material_override=mat
				child.add_child(glyph)
				glyph.position=Vector3(0,.015,(float(i)-1.5)*.48)
				glyph.scale.y=.15

func _prop_box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var visual=MeshInstance3D.new()
	var box=BoxMesh.new()
	box.size=size
	visual.mesh=box
	visual.position=at
	visual.material_override=material
	parent.add_child(visual)

func _finish_props() -> void:
	var crate: Node3D=game.get_node("Pickups/RootSeeds/Crate")
	var original: MeshInstance3D=crate.get_node("Mesh")
	var size: Vector3=original.mesh.get_aabb().size
	original.visible=false
	var wood=ShaderMaterial.new()
	wood.shader=PropShader
	wood.set_shader_parameter("base_color",Color("#a88450") if style_id=="A1" else Color("#777269"))
	# Separate slats, open top and corner posts read as an old seed crate.
	for i in range(4):
		var y=-size.y*.5+(float(i)+.5)*size.y/4.0
		for side in [-1.0,1.0]:
			_prop_box(crate,Vector3(0,y,side*(size.z*.5-.025)),Vector3(size.x,size.y/4.0-.018,.055),wood)
			_prop_box(crate,Vector3(side*(size.x*.5-.025),y,0),Vector3(.055,size.y/4.0-.018,size.z),wood)
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]:
			_prop_box(crate,Vector3(x*(size.x*.5-.05),0,z*(size.z*.5-.05)),Vector3(.085,size.y+.04,.085),wood)
	_prop_box(crate,Vector3(0,-size.y*.46,0),Vector3(size.x,.07,size.z),wood)
	var base: Node3D=game.get_node("Mechanisms/Altar/Base")
	var mat=ShaderMaterial.new()
	mat.shader=PropShader;mat.set_shader_parameter("wood",false)
	mat.set_shader_parameter("base_color",Color("#968164") if style_id=="A1" else Color("#6e7789"))
	base.get_node("Mesh").material_override=mat
	# Flush scored capstones give the altar a constructed surface and readable rim.
	for x in [-1.0,0.0,1.0]:
		for z in [-1.0,0.0,1.0]:
			_prop_box(base,Vector3(x*.70,.205,z*.70),Vector3(.68,.025,.68),mat)

func _atmosphere() -> void:
	var env: Environment=game.get_node("WorldEnvironment").environment
	var sky=Sky.new()
	sky_material=ShaderMaterial.new()
	sky_material.shader=SkyShader
	sky_material.set_shader_parameter("moon_garden",style_id=="D1")
	sky.sky_material=sky_material
	env.sky=sky
	env.fog_enabled=true
	env.fog_density=.008 if style_id=="A1" else .012
	env.fog_sky_affect=.15
	env.fog_light_color=Color("#aebfb2") if style_id=="A1" else Color("#717eab")
	env.fog_light_energy=.6
	if style_id=="D1":
		for at in [Vector3(-2.2,1.35,.25),Vector3(2.2,1.35,.25),
				Vector3(-2.4,1.6,-19.5),Vector3(2.4,1.6,-19.5),Vector3(0,1.0,-32)]:
			var glow=OmniLight3D.new()
			glow.position=at;glow.light_color=Color("#ffd294")
			glow.light_energy=.85;glow.omni_range=4.0
			add_child(glow)
			var seed=_old_model("root_seed",at-Vector3(0,.10,0),Vector3.ONE*.17,
				30.0,"WarmSeed_%s"%at)
			seed.set_meta("decorative_light",true)

func _collect_labels(node: Node) -> void:
	if node is Label3D:
		labels.append(node)
	for child in node.get_children():_collect_labels(child)

func _process(_delta: float) -> void:
	if not visual_ready:return
	var day=(sin((fmod(float(game.hours),24.0)-6.0)/24.0*TAU)+1.0)*.5
	sky_material.set_shader_parameter("daylight",day if style_id=="A1" else day*.50)
	# Keep close interaction cues readable; remove distant debug-like label clutter.
	for label in labels:
		if not is_instance_valid(label):continue
		var p=label.get_parent()
		var relevant=p.is_in_group("plots") or str(label.text).contains("源石") or str(label.text).contains("种子")
		var distance=game.player.global_position.distance_to(label.global_position)
		label.visible=relevant and distance<4.5

func get_report() -> Dictionary:
	var now_ids: Array[int]=[]
	_collision_inventory(game,now_ids)
	return {"ready":visual_ready,"errors":errors,"style":style_id,"counts":metrics,
		"collider_inventory_unchanged":collider_ids==now_ids,
		"required_generated_families":models.sources.keys(),"human_acceptance":"pending_review"}

func _exit_tree() -> void:
	models.clear()
