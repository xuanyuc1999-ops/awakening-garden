extends CanvasLayer

var game
var root: Control
var title_label: Label
var objective: Label
var stock: Label
var clock: Label
var prompt: Label
var notice: Label
var menu: Control
var menu_title: Label
var menu_body: Label
var primary: Button
var secondary: Button
var map: Control

func _ready() -> void:
	game = get_parent()
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var font = load("res://fonts/NotoSansCJKsc-Regular.otf")
	var theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	root.theme = theme
	var heading = panel(Vector2(24, 20), Vector2(570, 94))
	title_label = label(heading, "苏醒园地   /   灰盒原型", 27, Vector2(18, 12), Vector2(540, 36))
	clock = label(heading, "", 16, Vector2(18, 55), Vector2(540, 26))
	var task_panel = panel(Vector2(24, 128), Vector2(405, 150))
	label(task_panel, "本轮目标", 15, Vector2(18, 10), Vector2(370, 24), Color(0.70, 0.72, 0.74))
	objective = label(task_panel, "", 20, Vector2(18, 42), Vector2(370, 98))
	var inventory = panel(Vector2(-292, 20), Vector2(268, 166), true)
	label(inventory, "随身资源", 15, Vector2(18, 10), Vector2(230, 26), Color(0.7, 0.72, 0.74))
	stock = label(inventory, "", 19, Vector2(18, 43), Vector2(240, 115))
	var map_panel = panel(Vector2(-292, 200), Vector2(268, 240), true)
	label(map_panel, "园地示意   ·   北 ↑", 15, Vector2(18, 9), Vector2(230, 24), Color(0.7, 0.72, 0.74))
	map = Control.new()
	map.set_script(load("res://scripts/map.gd"))
	map.position = Vector2(16, 38)
	map.size = Vector2(236, 184)
	map.game = game
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(map)
	var action_panel = panel(Vector2(-400, -157), Vector2(800, 93))
	action_panel.anchor_left = 0.5
	action_panel.anchor_top = 1.0
	action_panel.anchor_right = 0.5
	action_panel.anchor_bottom = 1.0
	prompt = label(action_panel, "", 23, Vector2(20, 12), Vector2(760, 34))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice = label(action_panel, "", 16, Vector2(20, 53), Vector2(760, 28), Color(0.82, 0.83, 0.80))
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var footer = panel(Vector2(-680, -55), Vector2(1360, 37))
	footer.anchor_left = 0.5
	footer.anchor_top = 1.0
	footer.anchor_right = 0.5
	footer.anchor_bottom = 1.0
	var controls = label(footer, "WASD 移动  ·  Shift 快走  ·  右键拖动 / ← → 旋转  ·  滚轮缩放  ·  E 交互  ·  1 / 2 种子  ·  T 等待  ·  F 拔除  ·  H 返回  ·  Esc 暂停", 16, Vector2(10, 5), Vector2(1340, 27))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_menu()

func panel(at: Vector2, dimensions: Vector2, right: bool = false) -> Panel:
	var node = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12, 0.87)
	style.border_color = Color(0.40, 0.43, 0.44, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	node.add_theme_stylebox_override("panel", style)
	root.add_child(node)
	node.position = at
	node.size = dimensions
	if right:
		node.anchor_left = 1.0
		node.anchor_right = 1.0
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func label(parent: Control, text: String, font_size: int, at: Vector2, dimensions: Vector2, color: Color = Color(0.94, 0.94, 0.91)) -> Label:
	var node = Label.new()
	node.text = text
	node.position = at
	node.size = dimensions
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	var shade = ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.05, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var card = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.16, 0.98)
	style.border_color = Color(0.55, 0.59, 0.57)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", style)
	menu.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -320
	card.offset_right = 320
	card.offset_top = -235
	card.offset_bottom = 235
	label(card, "AWAKENING GARDEN   /   PLAYABLE GREYBOX", 14, Vector2(36, 25), Vector2(570, 24), Color(0.69, 0.73, 0.72))
	menu_title = label(card, "", 36, Vector2(36, 65), Vector2(570, 55))
	menu_body = label(card, "", 20, Vector2(36, 135), Vector2(570, 165))
	menu_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	primary = Button.new()
	primary.position = Vector2(36, 325)
	primary.size = Vector2(568, 51)
	card.add_child(primary)
	primary.pressed.connect(func(): game.menu_primary())
	secondary = Button.new()
	secondary.position = Vector2(36, 389)
	secondary.size = Vector2(274, 43)
	card.add_child(secondary)
	secondary.pressed.connect(func(): game.menu_secondary())
	var quit_button = Button.new()
	quit_button.text = "退出游戏"
	quit_button.position = Vector2(329, 389)
	quit_button.size = Vector2(275, 43)
	card.add_child(quit_button)
	quit_button.pressed.connect(func(): get_tree().quit())

func show_menu(mode: String) -> void:
	menu.visible = true
	match mode:
		"start":
			menu_title.text = "让园地重新醒来"
			menu_body.text = "先翻土，再播种、浇水。\n藤蔓在沟边成熟时搭桥；深根在碎石前成熟时开路。\n收获两份素材，在尽头唤醒源石。\n\n没有枯萎或时间惩罚。T 可立即推进一小时。"
			primary.text = "开始开垦   [ Enter ]"
			secondary.text = "重置原型"
		"pause":
			menu_title.text = "园地正在休息"
			menu_body.text = "游戏时间已暂停。\n1 选择藤蔓，2 选择深根植物。\nF 拔除会退还种子；H 返回安全位置。\nR 可重新开始整轮实验。"
			primary.text = "继续探索   [ Enter / Esc ]"
			secondary.text = "重新开始"
		"restart":
			menu_title.text = "重新开垦？"
			menu_body.text = "本轮种植、资源和两处机关将恢复初始状态。\n当前灰盒不保存进度。"
			primary.text = "确认重新开始   [ Enter ]"
			secondary.text = "取消"
		"win":
			menu_title.text = "园地已苏醒"
			menu_body.text = "藤蔓连起了断路，深根推开了碎石。\n收获的素材重新点亮源石，园地恢复生机。\n\n你可以继续种植，或重新开始测试。"
			primary.text = "继续探索   [ Enter ]"
			secondary.text = "重新开始"
	primary.grab_focus()

func update_hud() -> void:
	if game == null:
		return
	var hour = fmod(game.hours, 24.0)
	clock.text = "第 %d 天   %02d:%02d   ·   %s   ·   T +1 小时" % [int(game.hours / 24.0) + 1, int(hour), int(fmod(hour, 1.0) * 60.0), game.zone_name()]
	var a = "✓" if game.bridge_open else "○"
	var b = "✓" if game.gate_open else "○"
	var c = "✓" if game.won else "○"
	objective.text = "%s  沟边种藤蔓，长成一座桥\n%s  石前种深根，打开通路\n%s  收集 2 份素材，唤醒源石" % [a, b, c]
	stock.text = "%s  1  藤蔓种子     × %d\n%s  2  深根种子     × %d\n     作物素材        × %d" % ["▶" if game.selected_crop == 0 else "  ", game.seeds[0], "▶" if game.selected_crop == 1 else "  ", game.seeds[1], game.materials]
	if game.target != null:
		if game.target.is_in_group("plots"):
			prompt.text = game.target.action_text()
		elif game.target == game.seed_cache:
			prompt.text = "E  拾取古老的深根种子 × 2"
		else:
			prompt.text = "园地已复苏 · 继续种植" if game.won else "E  唤醒源石   ·   需要作物素材 2 份"
	else:
		prompt.text = "靠近有标记的地块，按 E 开始开垦" if not game.bridge_open else "沿新通路探索，寻找下一处种植标记"
	notice.text = game.toast if game.toast_time > 0 else "成熟植物自动打开机关；收获后，已打开的通路仍然保留。"
	map.queue_redraw()
