extends Node3D

enum Stage { HARD, TILLED, SOWN, GROWING, MATURE }
const CROP_NAMES = ["藤蔓", "深根植物"]
const CROP_COLORS = [Color(0.40, 0.67, 0.64), Color(0.76, 0.63, 0.40)]
const GROWTH_HOURS = 3.0

@export var plot_id: String = ""
@export var zone: int = 0
@export var required_crop: int = -1
var stage: int = Stage.HARD
var crop: int = -1
var growth: float = 0.0
var game
var plant: Node3D
var border: Node3D
var marker: Label3D
var selected = false

func _ready() -> void:
	game = get_tree().current_scene
	plant = Node3D.new()
	plant.name = "CropVisual"
	add_child(plant)
	border = Node3D.new()
	border.name = "TargetOutline"
	add_child(border)
	for index in range(4):
		var size = Vector3(2.65, 0.035, 0.055) if index < 2 else Vector3(0.055, 0.035, 2.65)
		var offset = Vector3(0, 0.23, (-1 if index == 0 else 1) * 1.3) if index < 2 else Vector3((-1 if index == 2 else 1) * 1.3, 0.23, 0)
		box(border, size, offset, Color(0.95, 0.88, 0.60))
	marker = $Marker
	refresh()

func available() -> bool:
	return game != null and (zone == 0 or (zone == 1 and game.bridge_open) or (zone == 2 and game.gate_open))

func target_position() -> Vector3:
	return global_position

func set_selected(value: bool) -> void:
	selected = value
	border.visible = selected and available()

func action_text() -> String:
	match stage:
		Stage.HARD:
			return "E  翻土开垦"
		Stage.TILLED:
			return "E  播种%s   ·   1 / 2 切换种子" % CROP_NAMES[game.selected_crop]
		Stage.SOWN:
			return "E  浇水   ·   F 拔除退还种子"
		Stage.GROWING:
			return "正在生长 %.0f%%   ·   T 等待一小时   ·   F 拔除" % (growth / GROWTH_HOURS * 100.0)
		Stage.MATURE:
			return "E  收获%s   →   种子 +2 / 素材 +1" % CROP_NAMES[crop]
	return ""

func interact() -> bool:
	if not available():
		game.message("这片区域尚未开放。")
		return false
	match stage:
		Stage.HARD:
			stage = Stage.TILLED
			game.record("plot.tilled", {"plot": plot_id})
			game.message("土地已松开。选择种子，再按 E 播种。")
		Stage.TILLED:
			var choice = game.selected_crop
			if game.seeds[choice] <= 0:
				game.message("没有这种种子。先收获已有作物，或寻找种子箱。")
				game.record("action.denied", {"reason": "no_seed", "plot": plot_id})
				return false
			crop = choice
			game.seeds[crop] -= 1
			stage = Stage.SOWN
			game.record("crop.sown", {"plot": plot_id, "crop": crop})
			game.message("种子已埋下。按 E 浇水；水源充足，不消耗资源。")
		Stage.SOWN:
			stage = Stage.GROWING
			growth = 0.0
			game.record("crop.watered", {"plot": plot_id})
			game.message("开始生长。按 T 推进一小时；三小时后成熟。")
		Stage.GROWING:
			game.message("水分充足，无需重复浇水。按 T 可以快进时间。")
			game.record("action.denied", {"reason": "not_mature", "plot": plot_id})
			return false
		Stage.MATURE:
			game.seeds[crop] += 2
			game.materials += 1
			game.record("crop.harvested", {"plot": plot_id, "crop": crop, "materials": game.materials})
			game.message("收获成功：种子 +2，作物素材 +1。已打开的通路会保留。")
			stage = Stage.TILLED
			crop = -1
			growth = 0.0
	refresh()
	return true

func uproot() -> bool:
	if stage < Stage.SOWN or not available():
		game.message("这里没有需要拔除的作物。")
		return false
	game.seeds[crop] += 1
	game.record("crop.uprooted", {"plot": plot_id, "crop": crop})
	stage = Stage.TILLED
	crop = -1
	growth = 0.0
	refresh()
	game.message("已拔除并退还 1 粒种子，可以重新种植。")
	return true

func advance(hours: float) -> void:
	if stage != Stage.GROWING:
		return
	var previous = growth
	growth = minf(growth + hours, GROWTH_HOURS)
	if growth >= GROWTH_HOURS:
		stage = Stage.MATURE
		game.record("crop.matured", {"plot": plot_id, "crop": crop})
		refresh()
		game.on_crop_matured(self)
	elif int(previous) != int(growth):
		refresh()

func reset_plot() -> void:
	stage = Stage.HARD
	crop = -1
	growth = 0.0
	refresh()

func refresh() -> void:
	if plant == null:
		return
	for child in plant.get_children():
		plant.remove_child(child)
		child.queue_free()
	border.visible = selected and available()
	var soil = StandardMaterial3D.new()
	soil.albedo_color = Color(0.31, 0.32, 0.31) if stage == Stage.HARD else Color(0.42, 0.40, 0.36)
	soil.roughness = 1.0
	$Soil.material_override = soil
	var prefix = "藤蔓 → 沟壑" if required_crop == 0 else "深根 → 碎石"
	var states = ["荒地", "已开垦", "等待浇水", "生长中", "可收获"]
	marker.text = (prefix + "\n" if required_crop >= 0 else "") + states[stage]
	marker.modulate = Color(0.85, 0.85, 0.82) if available() else Color(0.5, 0.5, 0.5)
	if stage == Stage.HARD:
		for i in range(3):
			box(plant, Vector3(0.24, 0.22, 0.3), Vector3(-0.65 + i * 0.6, 0.25, 0.22 * (i % 2)), Color(0.53, 0.54, 0.52))
	elif stage == Stage.TILLED:
		for i in range(4):
			box(plant, Vector3(0.1, 0.035, 1.8), Vector3(-0.75 + i * 0.5, 0.23, 0), Color(0.27, 0.27, 0.25))
	elif stage == Stage.SOWN:
		box(plant, Vector3(0.30, 0.16, 0.30), Vector3(0, 0.27, 0), CROP_COLORS[crop])
	else:
		var mature = stage == Stage.MATURE
		var height = (1.65 if crop == 0 else 1.2) if mature else 0.5 + growth * 0.18
		box(plant, Vector3(0.12, height, 0.12), Vector3(0, 0.22 + height / 2.0, 0), CROP_COLORS[crop] * 0.8)
		var leaves = 5 if mature else 2
		for i in range(leaves):
			var side = -1 if i % 2 == 0 else 1
			var leaf = box(plant, Vector3(0.65 if mature else 0.42, 0.10, 0.3), Vector3(side * 0.25, 0.4 + float(i) * height / leaves, 0), CROP_COLORS[crop])
			leaf.rotation.z = side * 0.32
		if mature and crop == 1:
			for i in range(3):
				var root = box(plant, Vector3(0.22, 0.34, 0.9), Vector3((i - 1) * 0.38, 0.28, 0), Color(0.72, 0.63, 0.47))
				root.rotation.y = (i - 1) * 0.6

func box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	node.material_override = material
	parent.add_child(node)
	return node
