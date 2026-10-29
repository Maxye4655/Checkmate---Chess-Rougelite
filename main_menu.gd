extends Control


const BOARD_SCENE_PATH := "res://board.tscn"

@onready var play_button: Button = $CenterContainer/MenuBox/PlayButton

var _leaving := false
var _ip_edit: LineEdit
var _status_label: Label
var _cancel_button: Button
var _join_row: HBoxContainer
var _lan_ip := ""

const HOVER_LIFT := 4.0
const HOVER_DURATION := 0.10
const INDICATOR_COLOR := Color("e0b94e")

var _button_tweens: Dictionary = {}
var _focused_button: Button

func _ready() -> void:
	var box := play_button.get_parent()

	# One horizontal row of buttons, like Balatro. The row takes the Play button's place in
	# MenuBox, so it sits wherever that button was (directly under the title).
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	box.move_child(row, play_button.get_index())
	play_button.reparent(row, false)

	play_button.text = "Single Player"
	_style_button(play_button)
	play_button.pressed.connect(_on_play_pressed)
	_add_button(row, "Local 2-Player", _on_local_pressed)
	_add_button(row, "Host Online", _on_host_pressed)
	_add_button(row, "Join Online", _on_join_pressed)

	# Second row, only shown after pressing "Join Online".
	_join_row = HBoxContainer.new()
	_join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_row.add_theme_constant_override("separation", 12)
	_join_row.hide()
	box.add_child(_join_row)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "Host IP address"
	_ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip_edit.custom_minimum_size = Vector2(300, 56)
	_ip_edit.add_theme_font_size_override("font_size", 22)
	_ip_edit.text_submitted.connect(func(_text): _on_connect_pressed())
	_join_row.add_child(_ip_edit)
	_add_button(_join_row, "Connect", _on_connect_pressed)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status_label)

	_cancel_button = _add_button(box, "Cancel", _on_cancel_pressed)
	_cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel_button.hide()

	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.upnp_finished.connect(_on_upnp_finished)

	play_button.grab_focus()


func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	_style_button(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


# --- Mode buttons

func _on_play_pressed() -> void:
	NetworkManager.close()
	GameConfig.mode = GameConfig.Mode.SINGLE
	GameConfig.player_color = ChessEngine.WHITE
	_go_to_board()


func _on_local_pressed() -> void:
	NetworkManager.close()
	GameConfig.mode = GameConfig.Mode.LOCAL
	GameConfig.player_color = ChessEngine.WHITE
	_go_to_board()


func _on_host_pressed() -> void:
	if NetworkManager.host_game() != OK:
		_status_label.text = "Could not host (is port %d already in use?)" % NetworkManager.PORT
		return
	_lan_ip = NetworkManager.get_local_ip()
	_status_label.text = "Waiting for an opponent...\nSame network: %s\nOpening the port for internet play..." % _lan_ip
	_cancel_button.show()
	NetworkManager.try_upnp()


func _on_join_pressed() -> void:
	_join_row.visible = not _join_row.visible
	if _join_row.visible:
		_ip_edit.grab_focus()


func _on_connect_pressed() -> void:
	var address := _ip_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	if NetworkManager.join_game(address) != OK:
		_status_label.text = "Could not start the connection."
		return
	_status_label.text = "Connecting to %s..." % address
	_cancel_button.show()


func _on_cancel_pressed() -> void:
	NetworkManager.close()
	_status_label.text = ""
	_cancel_button.hide()
	_join_row.hide()


# --- Network feedback (the match itself starts from NetworkManager)

func _on_connection_failed() -> void:
	_status_label.text = "Could not connect."
	_cancel_button.hide()


func _on_upnp_finished(success: bool, external_ip: String) -> void:
	if not _cancel_button.visible:
		return   # no longer hosting
	if success:
		_status_label.text = "Waiting for an opponent...\nSame network: %s\nInternet: %s" % [_lan_ip, external_ip]
	else:
		_status_label.text = "Waiting for an opponent...\nSame network: %s\nInternet play: forward UDP port %d on your router." % [_lan_ip, NetworkManager.PORT]


func _go_to_board() -> void:
	if _leaving:
		return
	_leaving = true

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
	button.custom_minimum_size = Vector2(210, 80)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var normal := _make_button_style(
		"res://Assets/UI/button_normal.png"
	)
	var hover := _make_button_style(
		"res://Assets/UI/button_hover.png"
	)
	var pressed := _make_button_style(
		"res://Assets/UI/button_pressed.png"
	)
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	
	button.add_theme_color_override(
		"font_color", Color("f5ead0")
	)
	button.add_theme_color_override(
		"font_hover_color", Color("ffffff")
	)
	button.add_theme_color_override(
		"font_pressed_color", Color("e3b753ff")
 	)
	button.add_theme_color_override(
		"font_focus_color", Color("ffffff")
	)
	
	button.add_theme_font_size_override("font_size", 24)
	
	# Hover Animation.
	button.mouse_entered.connect(
		func(): _animate_button(button, true)
	)
	button.mouse_exited.connect(
		func(): _animate_button(button, false)
	)

func _make_button_style(path: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(path)
	
	style.texture_margin_left = 8
	style.texture_margin_right = 8
	style.texture_margin_top = 8
	style.texture_margin_bottom = 8
	
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_bottom = 8
	style.texture_margin_top = 8
	
	return style

func _animate_button(button: Button, hovering: bool) -> void:
	if _button_tweens.has(button):
		var old_tween: Tween = _button_tweens[button]
		if old_tween.is_valid():
			old_tween.kill()
	
	var target_y := -HOVER_LIFT if hovering else 0.0
	
	var tween := create_tween()
	_button_tweens[button] = tween
	
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		button, "position:y", target_y, HOVER_DURATION
	)
	
	if not hovering:
		tween.tween_callback(
			func(): _button_tweens.erase(button)
		)

func _draw() -> void:
	if not is_instance_valid(_focused_button):
		return
	
	if not _focused_button.is_visible_in_tree():
		return
	
	var rect := _focused_button.get_global_rect()
	var center := Vector2(
		rect.position.x - 12,
		rect.position.y + rect.size.y / 2.0
	)
	
	var points := PackedVector2Array([
		center + Vector2(0, -5),
		center + Vector2(5, 0),
		center + Vector2(0, 5),
		center + Vector2(-5, 0)
	])
	
	draw_colored_polygon(points, INDICATOR_COLOR)
