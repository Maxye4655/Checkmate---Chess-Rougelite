extends Control


const BOARD_SCENE_PATH := "res://board.tscn"

@onready var play_button: Button = $CenterContainer/MenuBox/PlayButton

var _leaving := false


func _ready() -> void:
	_style_button(play_button)
	play_button.pressed.connect(_on_play_pressed)
	play_button.grab_focus()


func _on_play_pressed() -> void:
	if _leaving:
		return
	_leaving = true

	GameConfig.player_color = ChessEngine.WHITE

	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.modulate = Color(1, 1, 1, 0)
	add_child(fade)

	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 1.0, 0.35)
	await tween.finished
	get_tree().change_scene_to_file(BOARD_SCENE_PATH)


func _style_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(300, 84)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("3d5662ff")
	normal.border_color = Color("648a9dff")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10

	var hover := normal.duplicate()
	hover.bg_color = Color("648a9dff")
	hover.border_color = Color("ffffffff")

	var pressed := normal.duplicate()
	pressed.bg_color = Color("212e35ff")

	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color("ffffffff")

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color("ffffffff"))
	button.add_theme_color_override("font_hover_color", Color("212e35ff"))
	button.add_theme_color_override("font_pressed_color", Color("96a2a8ff"))
	button.add_theme_color_override("font_focus_color", Color("ffffffff"))
	button.add_theme_font_size_override("font_size", 28)
