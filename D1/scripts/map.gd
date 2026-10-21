extends Control

var game

func _draw() -> void:
	if game == null or game.player == null:
		return
	var center = 71.0
	var scale_z = 2.9
	var y_top = 8.0
	var start_y = y_top + 36.0 * scale_z
	draw_rect(Rect2(center - 29, start_y, 58, 18 * scale_z), Color(0.45, 0.47, 0.46))
	draw_rect(Rect2(center - 29, y_top + 16 * scale_z, 58, 14 * scale_z), Color(0.45, 0.47, 0.46) if game.bridge_open else Color(0.25, 0.27, 0.28))
	draw_rect(Rect2(center - 29, y_top, 58, 16 * scale_z), Color(0.49, 0.53, 0.46) if game.gate_open else Color(0.25, 0.27, 0.28))
	draw_line(Vector2(center, y_top + 30 * scale_z), Vector2(center, start_y), Color(0.4, 0.75, 0.7) if game.bridge_open else Color(0.45, 0.47, 0.48), 5.0)
	draw_line(Vector2(center - 29, y_top + 16 * scale_z), Vector2(center + 29, y_top + 16 * scale_z), Color(0.75, 0.64, 0.4) if not game.gate_open else Color(0.38, 0.45, 0.38), 4.0)
	var p = game.player.position
	draw_circle(Vector2(center + p.x * 2.9, y_top + (p.z + 36.0) * scale_z), 4.5, Color(1, 0.95, 0.72))
	var font = get_theme_default_font()
	draw_string(font, Vector2(115, 28), "03  源石", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.87, 0.85))
	draw_string(font, Vector2(115, 84), "02  碎石", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.87, 0.85))
	draw_string(font, Vector2(115, 144), "01  起始", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.87, 0.85))
