extends Node2D
## Single-player chess board: rendering, input, animations and game-over flow.

# --- Scenes & layout ---------------------------------------------------------
const MAIN_MENU_SCENE_PATH := "res://main_menu.tscn"
const BASE_RESOLUTION := Vector2(1152, 648)
const TILE_SIZE: int = 72
const BOARD_SIZE: int = 8 * TILE_SIZE
const BOARD_RIGHT_MARGIN: int = 48
const FRAME_PADDING: float = 14.0
const HUD_MARGIN := Vector2(40, 48)
const TITLE_WIDTH := 207.0

# --- Pieces ------------------------------------------------------------------
const PIECE_SCALE := 0.99072        # 0.86 * 1.2 * 1.2 * 0.8
const PAWN_SCALE_FACTOR := 0.85
const PIECE_FILES := ["", "pawn", "knight", "bishop", "rook", "queen", "king"]
const WHITE_KING_CODE := 6
const PIECE_SHADOW := Color(0, 0, 0, 0.28)
const PIECE_SHADOW_OFFSET := Vector2(2, 4)

# --- Palette -----------------------------------------------------------------
const LIGHT_SQUARE := Color("96a2a8ff")
const DARK_SQUARE := Color("3d5662ff")
const BOARD_FRAME := Color("464c4eff")
const BOARD_FRAME_INNER := Color("648a9dff")

const SELECT_FILL := Color("648a9d8c")
const SELECT_LINE := Color("ffffffff")
const LAST_MOVE_FILL := Color("648a9d52")
const HOVER_FILL := Color(1, 1, 1, 0.12)
const CHECK_FILL := Color(0.66, 0.28, 0.28, 0.55)
const MOVE_DOT := Color("212e3599")
const MOVE_CAPTURE := Color(0.72, 0.34, 0.30, 0.90)

const BG := Color("212e35ff")
const TEXT := Color("ffffffff")
const TEXT_DIM := Color("96a2a8ff")
const ACCENT := Color("648a9dff")
const OVERLAY_DIM := Color(0.129, 0.18, 0.208, 0.82)

# --- Timings (seconds) -------------------------------------------------------
const MOVE_ANIM_TIME := 0.18
const CLICK_ANIM_TIME := 0.22
const RESET_ANIM_TIME := 0.45
const AI_THINK_DELAY := 0.2
const MENU_FADE_TIME := 0.35
const LOSE_COUNTDOWN := 10.0
const LOSE_WARNING_TIME := 3.0

const FILES := "abcdefgh"


## Tiny helper so every animation shares the same progress logic.
class Anim:
	var t := 1.0
	var duration := 0.2

	func start(seconds: float) -> void:
		t = 0.0
		duration = seconds

	func stop() -> void:
		t = 1.0

	func is_active() -> bool:
		return t < 1.0

	func step(delta: float) -> void:
		if t < 1.0:
			t = minf(t + delta / duration, 1.0)


# --- Core objects ------------------------------------------------------------
var engine: ChessEngine
var ai: ChessAI
var font: Font
var piece_textures := {}
var title_texture: Texture2D

var _frame_style: StyleBoxFlat
var _title_size := Vector2.ZERO

# --- Game state --------------------------------------------------------------
var selected := Vector2i(-1, -1)
var legal_for_selected: Array = []
var hover := Vector2i(-1, -1)
var _status: int = 0
var _leaving := false
var _ai_thinking := false
var _ai_generation := 0          # bumped on reset so stale AI turns are discarded

# --- Animations --------------------------------------------------------------
var _move_anim := Anim.new()
var _move_from := Vector2i.ZERO
var _move_to := Vector2i.ZERO
var _move_code := 0
var _click_anim := Anim.new()
var _click_square := Vector2i(-1, -1)
var _reset_anim := Anim.new()

# --- Game-over UI ------------------------------------------------------------
var _game_over_layer: CanvasLayer = null
var _lose_timer := 0.0
var _heart_piece: TextureRect = null
var _timer_label: Label = null
var _heart_tween: Tween = null
var _fade_overlay: ColorRect = null


# =============================================================================
# Setup
# =============================================================================

func _ready() -> void:
	engine = ChessEngine.new()
	ai = ChessAI.new()
	font = load("res://Assets/CheckMate.ttf")
	title_texture = load("res://Assets/Title.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	for t in range(1, 7):
		piece_textures[t] = _load_piece_texture(t)
		piece_textures[-t] = _load_piece_texture(-t)

	_title_size = Vector2(TITLE_WIDTH, TITLE_WIDTH * title_texture.get_height() / title_texture.get_width())
	_frame_style = _make_box(BOARD_FRAME, BOARD_FRAME_INNER, 10, 3)
	_frame_style.shadow_color = Color(0, 0, 0, 0.35)
	_frame_style.shadow_size = 18
	_frame_style.shadow_offset = Vector2(0, 6)

	_refresh_status()
	queue_redraw()
	_maybe_ai_move()


func _load_piece_texture(code: int) -> Texture2D:
	var base: String = PIECE_FILES[absi(code)]
	var prefix := "W" if code > 0 else "B"
	var path := "res://Assets/%s_%s.png" % [prefix, base.capitalize()]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_warning("No texture found for piece '%s' (%s)" % [base, path])
	return null


# =============================================================================
# Coordinate helpers (the board is flipped when the player is Black)
# =============================================================================

func _is_flipped() -> bool:
	return GameConfig.player_color != ChessEngine.WHITE


## Maps board <-> screen squares. Flipping is its own inverse.
func _to_view(square: Vector2i) -> Vector2i:
	return Vector2i(7 - square.x, 7 - square.y) if _is_flipped() else square


func get_board_origin() -> Vector2:
	return Vector2(
		BASE_RESOLUTION.x - BOARD_SIZE - BOARD_RIGHT_MARGIN,
		(BASE_RESOLUTION.y - BOARD_SIZE) / 2.0
	)


func _square_rect(square: Vector2i) -> Rect2:
	var view := _to_view(square)
	return Rect2(get_board_origin() + Vector2(view) * TILE_SIZE, Vector2(TILE_SIZE, TILE_SIZE))


func _square_center(square: Vector2i) -> Vector2:
	return _square_rect(square).get_center()


func _position_to_square(pos: Vector2) -> Vector2i:
	var rel := pos - get_board_origin()
	var col := int(floor(rel.x / TILE_SIZE))
	var row := int(floor(rel.y / TILE_SIZE))
	if col < 0 or col > 7 or row < 0 or row > 7:
		return Vector2i(-1, -1)
	return _to_view(Vector2i(col, row))


func _piece_scale_factor(code: int) -> float:
	return PAWN_SCALE_FACTOR if absi(code) == ChessEngine.Type.PAWN else 1.0


func _color_name(color: int) -> String:
	return "White" if color == ChessEngine.WHITE else "Black"


func _refresh_status() -> void:
	_status = engine.status()


func _is_game_over() -> bool:
	return _status == ChessEngine.Status.CHECKMATE or _status == ChessEngine.Status.STALEMATE


# =============================================================================
# Drawing
# =============================================================================

func _draw() -> void:
	var origin := get_board_origin()
	_draw_board(origin)
	_draw_highlights()
	_draw_coordinates(origin)
	_draw_pieces()
	_draw_title()
	_draw_hud()


func _draw_board(origin: Vector2) -> void:
	var pad := Vector2(FRAME_PADDING, FRAME_PADDING)
	draw_style_box(_frame_style, Rect2(origin - pad, Vector2(BOARD_SIZE, BOARD_SIZE) + pad * 2.0))

	for row in range(8):
		for col in range(8):
			var rect := Rect2(origin + Vector2(col, row) * TILE_SIZE, Vector2(TILE_SIZE, TILE_SIZE))
			draw_rect(rect, LIGHT_SQUARE if (row + col) % 2 == 0 else DARK_SQUARE)


func _draw_highlights() -> void:
	for square in engine.last_move:
		draw_rect(_square_rect(square), LAST_MOVE_FILL)

	if hover != Vector2i(-1, -1) and hover != selected:
		draw_rect(_square_rect(hover), HOVER_FILL)

	if selected != Vector2i(-1, -1):
		var rect := _square_rect(selected)
		draw_rect(rect, SELECT_FILL)
		draw_rect(rect.grow(-4), SELECT_LINE, false, 4.0)

	if _status == ChessEngine.Status.CHECK or _status == ChessEngine.Status.CHECKMATE:
		var king := engine.find_king(engine.board, engine.turn)
		if king != Vector2i(-1, -1):
			draw_rect(_square_rect(king), CHECK_FILL)

	for to in legal_for_selected:
		var center := _square_center(to)
		if engine.piece_at(to) == ChessEngine.Type.EMPTY:
			draw_circle(center, TILE_SIZE * 0.15, MOVE_DOT)
		else:
			draw_arc(center, TILE_SIZE * 0.40, 0.0, TAU, 40, MOVE_CAPTURE, 7.0, true)


func _draw_coordinates(origin: Vector2) -> void:
	var flipped := _is_flipped()
	for i in range(8):
		var file_label: String = FILES[7 - i if flipped else i]
		var w := font.get_string_size(file_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var x := origin.x + (i + 0.5) * TILE_SIZE
		draw_string(font, Vector2(x - w / 2.0, origin.y + BOARD_SIZE + 30), file_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_DIM)

		var rank_label := str(i + 1) if flipped else str(8 - i)
		var y := origin.y + (i + 0.5) * TILE_SIZE + 6
		draw_string(font, Vector2(origin.x - 30, y), rank_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_DIM)


func _draw_pieces() -> void:
	var reset_scale := 1.0
	if _reset_anim.is_active():
		var p := _reset_anim.t
		reset_scale = sin(p * PI * 0.5) * (1.0 + 0.2 * sin((1.0 - p) * PI * 2.0))

	var moving := _move_anim.is_active()
	for r in range(8):
		for c in range(8):
			var square := Vector2i(c, r)
			if moving and square == _move_to:
				continue
			var code: int = engine.board[r][c]
			if code == ChessEngine.Type.EMPTY:
				continue
			_draw_piece(code, _square_center(square), _click_scale(square) * reset_scale)

	if moving:
		var pos := _square_center(_move_from).lerp(_square_center(_move_to), _ease_out(_move_anim.t))
		_draw_piece(_move_code, pos, reset_scale)


func _draw_piece(code: int, center: Vector2, scale_mult: float) -> void:
	var texture: Texture2D = piece_textures.get(code)
	if texture == null:
		return
	var size := TILE_SIZE * PIECE_SCALE * _piece_scale_factor(code) * scale_mult
	var rect := Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size))
	draw_texture_rect(texture, Rect2(rect.position + PIECE_SHADOW_OFFSET * scale_mult, rect.size), false, PIECE_SHADOW)
	draw_texture_rect(texture, rect, false)


func _click_scale(square: Vector2i) -> float:
	if not _click_anim.is_active() or _click_square != square:
		return 1.0
	return 1.0 + 0.16 * sin(PI * _click_anim.t)


func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


func _draw_title() -> void:
	draw_texture_rect(title_texture, Rect2(HUD_MARGIN, _title_size), false)


func _draw_hud() -> void:
	var x := HUD_MARGIN.x
	var y := HUD_MARGIN.y + _title_size.y + 30.0

	var mode_label := "Single Player  (You are %s)" % _color_name(GameConfig.player_color)
	draw_string(font, Vector2(x, y), mode_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_DIM)
	draw_string(font, Vector2(x, y + 38), _status_line(), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ACCENT)

	var hint := "R  New game        Z  Undo        Esc  Menu"
	draw_string(font, Vector2(x, BASE_RESOLUTION.y - 28), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_DIM)


func _status_line() -> String:
	if _status == ChessEngine.Status.CHECKMATE:
		return "Checkmate"
	if _status == ChessEngine.Status.STALEMATE:
		return "Stalemate"
	if _ai_thinking or engine.turn != GameConfig.player_color:
		var dots := ".".repeat(int(Time.get_ticks_msec() * 0.0025) % 4)
		return "Computer is thinking" + dots
	var line := _color_name(engine.turn) + " to move"
	if _status == ChessEngine.Status.CHECK:
		line += "  -  Check!"
	return line


# =============================================================================
# Frame update
# =============================================================================

func _process(delta: float) -> void:
	var animating := _ai_thinking  # keeps the "thinking..." dots moving
	for anim in [_move_anim, _click_anim, _reset_anim]:
		if anim.is_active():
			anim.step(delta)
			animating = true
	if animating:
		queue_redraw()

	_update_lose_countdown(delta)


func _update_lose_countdown(delta: float) -> void:
	if _lose_timer <= 0.0:
		return
	_lose_timer -= delta

	if is_instance_valid(_timer_label):
		_timer_label.text = str(maxi(ceili(_lose_timer), 0))
		if _lose_timer <= LOSE_WARNING_TIME:
			_timer_label.add_theme_color_override("font_color", MOVE_CAPTURE)

	# Screen fades progressively to black as the timer runs out.
	if is_instance_valid(_fade_overlay):
		_fade_overlay.color.a = clampf(1.0 - _lose_timer / LOSE_COUNTDOWN, 0.0, 1.0)

	if _lose_timer <= 0.0:
		_lose_timer = 0.0
		_leave_to_menu()


# =============================================================================
# Input
# =============================================================================

# Uses _input (not _unhandled_input) so UI elsewhere in the scene can't swallow
# board clicks. _can_interact() already blocks clicks once the game is over.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var square := _position_to_square(event.position)
		if square != hover:
			hover = square
			queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				_new_game()
			KEY_Z, KEY_BACKSPACE:
				_undo()
			KEY_ESCAPE:
				_leave_to_menu()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_clear_selection()
			queue_redraw()


func _can_interact() -> bool:
	return not _ai_thinking and not _is_game_over() and engine.turn == GameConfig.player_color


func _handle_click(pos: Vector2) -> void:
	if not _can_interact():
		return

	var square := _position_to_square(pos)
	if square == Vector2i(-1, -1):
		_clear_selection()
		queue_redraw()
		return

	if selected != Vector2i(-1, -1) and square in legal_for_selected:
		_make_move(selected, square)
		_clear_selection()
		queue_redraw()
		_maybe_ai_move()
		return

	var code := engine.piece_at(square)
	if code != ChessEngine.Type.EMPTY and ChessEngine.color_of(code) == engine.turn:
		selected = square
		legal_for_selected = engine.legal_moves(square)
		_click_square = square
		_click_anim.start(CLICK_ANIM_TIME)
	else:
		_clear_selection()
	queue_redraw()


func _clear_selection() -> void:
	selected = Vector2i(-1, -1)
	legal_for_selected = []


# =============================================================================
# Game flow
# =============================================================================

func _make_move(from: Vector2i, to: Vector2i) -> void:
	engine.make_move(from, to)
	_move_from = from
	_move_to = to
	_move_code = engine.piece_at(to)
	_move_anim.start(MOVE_ANIM_TIME)
	_click_anim.stop()
	_refresh_status()
	_check_game_state()


func _maybe_ai_move() -> void:
	if _ai_thinking or engine.turn == GameConfig.player_color or _is_game_over():
		return

	_ai_thinking = true
	var generation := _ai_generation
	queue_redraw()

	await get_tree().create_timer(AI_THINK_DELAY).timeout
	# The game may have been reset or the scene left while we waited.
	if not is_inside_tree() or generation != _ai_generation:
		return

	var move: Array = ai.choose_move(engine)
	_ai_thinking = false
	if move.size() == 2:
		_make_move(move[0], move[1])
	_clear_selection()
	queue_redraw()


func _new_game() -> void:
	_ai_generation += 1
	_ai_thinking = false
	_clear_game_over()
	engine.reset()
	_reset_view_state()
	_maybe_ai_move()


func _undo() -> void:
	if _ai_thinking:
		return
	# Roll back until it is the player's turn again (undoes the AI reply too).
	for i in range(2):
		if engine.history.is_empty():
			break
		engine.undo()
		if engine.turn == GameConfig.player_color:
			break
	_clear_game_over()
	_reset_view_state()
	_maybe_ai_move()


func _reset_view_state() -> void:
	_refresh_status()
	_clear_selection()
	hover = Vector2i(-1, -1)
	_move_anim.stop()
	_click_anim.stop()
	_reset_anim.start(RESET_ANIM_TIME)
	queue_redraw()


func _leave_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	_clear_game_over()

	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.modulate.a = 0.0
	layer.add_child(fade)

	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 1.0, MENU_FADE_TIME)
	await tween.finished
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


# =============================================================================
# Game-over menus
# =============================================================================

func _check_game_state() -> void:
	if not _is_game_over():
		_clear_game_over()
		return
	if _game_over_layer != null:
		return

	if _status == ChessEngine.Status.STALEMATE:
		_show_draw_menu()
	elif engine.turn == GameConfig.player_color:
		_show_lose_menu()
	else:
		_show_win_menu()


func _show_win_menu() -> void:
	var vbox := _open_game_over_menu("Checkmate!", "You defeated the opponent.")
	vbox.add_child(_make_button("Play Again", _new_game))
	vbox.add_child(_make_button("Quit to Menu", _leave_to_menu))


func _show_draw_menu() -> void:
	var vbox := _open_game_over_menu("Draw", "The game ended in stalemate.")
	vbox.add_child(_make_button("Play Again", _new_game))
	vbox.add_child(_make_button("Quit to Menu", _leave_to_menu))


func _show_lose_menu() -> void:
	var vbox := _open_game_over_menu("You lose", "", true)

	_heart_piece = TextureRect.new()
	_heart_piece.texture = piece_textures[WHITE_KING_CODE]
	_heart_piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_heart_piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_heart_piece.custom_minimum_size = Vector2(120, 120)
	_heart_piece.pivot_offset = Vector2(60, 60)
	vbox.add_child(_heart_piece)

	_timer_label = _make_label(str(int(LOSE_COUNTDOWN)), 48, TEXT)
	vbox.add_child(_timer_label)

	vbox.add_child(_make_button("Continue Playing", _new_game))
	vbox.add_child(_make_button("Quit", _leave_to_menu))

	_lose_timer = LOSE_COUNTDOWN
	_play_heartbeat(_heart_piece)


## Builds the shared dim backdrop + centered panel and returns the panel's VBox.
func _open_game_over_menu(title_text: String, subtitle: String, with_fade: bool = false) -> VBoxContainer:
	_game_over_layer = CanvasLayer.new()
	add_child(_game_over_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = OVERLAY_DIM
	_game_over_layer.add_child(dim)

	if with_fade:
		_fade_overlay = ColorRect.new()
		_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade_overlay.color = Color(0, 0, 0, 0)
		_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_game_over_layer.add_child(_fade_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_layer.add_child(center)

	var panel := PanelContainer.new()
	var style := _make_box(BOARD_FRAME, BOARD_FRAME_INNER, 6, 3)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	vbox.add_child(_make_label(title_text, 38, ACCENT))
	if subtitle != "":
		vbox.add_child(_make_label(subtitle, 18, TEXT))

	_animate_menu_popup(panel)
	return vbox


func _clear_game_over() -> void:
	if _heart_tween and _heart_tween.is_valid():
		_heart_tween.kill()
	_heart_tween = null

	if _game_over_layer != null:
		_game_over_layer.queue_free()
		_game_over_layer = null

	_heart_piece = null
	_timer_label = null
	_fade_overlay = null
	_lose_timer = 0.0


func _animate_menu_popup(target: Control) -> void:
	target.scale = Vector2(0.6, 0.6)
	target.modulate.a = 0.0

	# Container sizes are only known after the first layout pass.
	await get_tree().process_frame
	if not is_instance_valid(target):
		return
	target.pivot_offset = target.size / 2.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(target, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play_heartbeat(target: Control) -> void:
	_heart_tween = create_tween().set_loops()
	_heart_tween.tween_property(target, "scale", Vector2(1.2, 1.2), 0.15)
	_heart_tween.tween_property(target, "scale", Vector2.ONE, 0.15)
	_heart_tween.tween_interval(0.2)
	_heart_tween.tween_property(target, "scale", Vector2(1.1, 1.1), 0.1)
	_heart_tween.tween_property(target, "scale", Vector2.ONE, 0.1)
	_heart_tween.tween_interval(0.4)


# =============================================================================
# UI factories
# =============================================================================

func _make_box(bg: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	return box


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220, 45)
	button.focus_mode = Control.FOCUS_NONE

	button.add_theme_stylebox_override("normal", _make_box(DARK_SQUARE, BOARD_FRAME_INNER, 4, 2))
	button.add_theme_stylebox_override("hover", _make_box(BOARD_FRAME_INNER, TEXT, 4, 2))
	button.add_theme_stylebox_override("pressed", _make_box(BG, ACCENT, 4, 2))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_font_size_override("font_size", 18)

	button.pressed.connect(on_pressed)
	return button
