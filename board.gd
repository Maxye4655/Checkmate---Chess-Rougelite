extends Node2D
## Single-player chess "run": board rendering, input, animations, and the
## win / lose / shop loop. Run-wide data lives in RunState, the shop in ShopScreen.

# --- Scenes & layout ---------------------------------------------------------
const MAIN_MENU_SCENE_PATH := "res://main_menu.tscn"
const BASE_RESOLUTION := Vector2(1152, 648)
const TILE_SIZE: int = 72
const BOARD_SIZE: int = 8 * TILE_SIZE
const BOARD_RIGHT_MARGIN: int = 48
const FRAME_PADDING: float = 14.0
const HUD_MARGIN := Vector2(40, 48)
const TITLE_WIDTH := 207.0

# --- Assets ------------------------------------------------------------------
const FONT_PATH := "res://Assets/CheckMate.ttf"
const TITLE_PATH := "res://Assets/Title.png"
const COIN_PATH := "res://Assets/UI/coin.png"                  # optional (16x16)
const CRACKED_KING_PATH := "res://Assets/W_King_Cracked.png"   # optional, same size as W_King.png

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
const GOLD := Color("f2c14e")
const OVERLAY_DIM := Color(0.129, 0.18, 0.208, 0.82)

# --- Timings (seconds) -------------------------------------------------------
const MOVE_ANIM_TIME := 0.18
const CLICK_ANIM_TIME := 0.22
const RESET_ANIM_TIME := 0.45
const AI_THINK_DELAY := 0.2
const MENU_FADE_TIME := 0.35
const TOAST_TIME := 2.2

# --- Defeat sequence ---------------------------------------------------------
const DEFEAT_SHAKE_TIME := 0.55
const DEFEAT_SHAKE_STRENGTH := 14.0
const DEFEAT_MENU_DELAY := 0.75
const LOSE_COUNTDOWN := 10.0
const LOSE_WARNING_TIME := 3.0
const FALLING_PIECE_COUNT := 16
const SECOND_WIND_PLIES := 4

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
var run: RunState
var font: Font
var piece_textures := {}
var title_texture: Texture2D
var coin_texture: Texture2D

var _frame_style: StyleBoxFlat
var _title_size := Vector2.ZERO

# --- Round state -------------------------------------------------------------
var selected := Vector2i(-1, -1)
var legal_for_selected: Array = []
var hover := Vector2i(-1, -1)
var _status: int = 0
var _leaving := false
var _ai_thinking := false
var _round_token := 0               # bumped each round so stale async work is discarded
var _round_enemy_material := 0
var _round_settled := false
var _last_reward: Dictionary = {}
var _toast_text := ""
var _toast_timer := 0.0

# --- Animations --------------------------------------------------------------
var _move_anim := Anim.new()
var _move_from := Vector2i.ZERO
var _move_to := Vector2i.ZERO
var _move_code := 0
var _click_anim := Anim.new()
var _click_square := Vector2i(-1, -1)
var _reset_anim := Anim.new()
var _shake_anim := Anim.new()

# --- Game-over / shop UI -----------------------------------------------------
var _shop: ShopScreen = null
var _game_over_layer: CanvasLayer = null
var _defeat_pending := false
var _lose_timer := 0.0
var _last_tick := 0
var _beat_phase := 0.0
var _crack_applied := false
var _heart_piece: TextureRect = null
var _timer_label: Label = null
var _fade_overlay: ColorRect = null


# =============================================================================
# Setup
# =============================================================================

func _ready() -> void:
	engine = ChessEngine.new()
	ai = ChessAI.new()
	run = RunState.new()
	font = load(FONT_PATH)
	title_texture = load(TITLE_PATH)
	coin_texture = _load_optional(COIN_PATH)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	for t in range(1, 7):
		piece_textures[t] = _load_piece_texture(t)
		piece_textures[-t] = _load_piece_texture(-t)

	_title_size = Vector2(TITLE_WIDTH, TITLE_WIDTH * title_texture.get_height() / title_texture.get_width())
	_frame_style = _make_box(BOARD_FRAME, BOARD_FRAME_INNER, 10, 3)
	_frame_style.shadow_color = Color(0, 0, 0, 0.35)
	_frame_style.shadow_size = 18
	_frame_style.shadow_offset = Vector2(0, 6)

	_start_round()


func _load_optional(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


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


func _toast(message: String) -> void:
	_toast_text = message
	_toast_timer = TOAST_TIME
	queue_redraw()


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
	_draw_run_info(x, y + 92.0)

	if _toast_timer > 0.0:
		var color := Color(GOLD, clampf(_toast_timer, 0.0, 1.0))
		draw_string(font, Vector2(x, BASE_RESOLUTION.y - 64), _toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)

	var hint := "R  New run        Z  Undo        Esc  Menu"
	draw_string(font, Vector2(x, BASE_RESOLUTION.y - 28), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_DIM)


func _draw_run_info(x: float, y: float) -> void:
	draw_string(font, Vector2(x, y), "Round %d" % run.round_number, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT)
	y += 40.0

	var coin_pos := Vector2(x, y - 26.0)
	if coin_texture:
		draw_texture_rect(coin_texture, Rect2(coin_pos, Vector2(32, 32)), false)
	else:
		draw_circle(coin_pos + Vector2(16, 16), 13.0, GOLD)
		draw_arc(coin_pos + Vector2(16, 16), 13.0, 0.0, TAU, 24, GOLD.darkened(0.4), 2.0, true)
	draw_string(font, Vector2(x + 42.0, y), str(run.coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GOLD)
	y += 32.0

	draw_string(font, Vector2(x, y), "Undos  %d" % run.undos_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_DIM)
	y += 26.0
	if run.extra_lives > 0:
		draw_string(font, Vector2(x, y), "Second Winds  %d" % run.extra_lives, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_DIM)
		y += 26.0
	if run.enemy_queens > 0:
		draw_string(font, Vector2(x, y), "Enemy Queens  %d" % run.enemy_queens, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MOVE_CAPTURE)


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

	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
		animating = true

	if _shake_anim.is_active():
		_shake_anim.step(delta)
		var falloff := 1.0 - _shake_anim.t
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * DEFEAT_SHAKE_STRENGTH * falloff
		if not _shake_anim.is_active():
			position = Vector2.ZERO

	if animating:
		queue_redraw()

	_update_lose_countdown(delta)


func _update_lose_countdown(delta: float) -> void:
	if _lose_timer <= 0.0:
		return
	_lose_timer -= delta
	var progress := 1.0 - clampf(_lose_timer / LOSE_COUNTDOWN, 0.0, 1.0)

	if is_instance_valid(_timer_label):
		var seconds := maxi(ceili(_lose_timer), 0)
		_timer_label.text = str(seconds)
		if seconds != _last_tick:
			_last_tick = seconds
			_punch(_timer_label, 1.5)
		if _lose_timer <= LOSE_WARNING_TIME:
			_timer_label.add_theme_color_override("font_color", MOVE_CAPTURE)

	if is_instance_valid(_heart_piece):
		_update_heart(delta, progress)

	# The screen fades progressively to black as the timer runs out.
	if is_instance_valid(_fade_overlay):
		_fade_overlay.color.a = progress

	if _lose_timer <= 0.0:
		_lose_timer = 0.0
		_leave_to_menu()


## A lub-dub heartbeat that slows, dims and finally cracks as time runs out.
func _update_heart(delta: float, progress: float) -> void:
	var period := lerpf(0.7, 2.2, progress)
	_beat_phase = fposmod(_beat_phase + delta / period, 1.0)
	var pulse := exp(-pow((_beat_phase - 0.08) / 0.06, 2.0)) \
			+ 0.6 * exp(-pow((_beat_phase - 0.30) / 0.06, 2.0))
	var strength := lerpf(0.22, 0.06, progress)
	_heart_piece.scale = Vector2.ONE * (1.0 + strength * pulse)
	_heart_piece.modulate = Color.WHITE.lerp(Color(0.55, 0.3, 0.3, 0.85), progress)

	if not _crack_applied and _lose_timer <= LOSE_WARNING_TIME:
		_crack_applied = true
		var cracked := _load_optional(CRACKED_KING_PATH)
		if cracked:
			_heart_piece.texture = cracked


# =============================================================================
# Input
# =============================================================================

# _input (not _unhandled_input) so other UI in the scene can't swallow board clicks.
# _can_interact() already blocks board clicks once the game is over or the shop is open.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _shop != null:
			return
		var square := _position_to_square(event.position)
		if square != hover:
			hover = square
			queue_redraw()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				if _shop == null:
					_new_run()
			KEY_Z, KEY_BACKSPACE:
				_undo()
			KEY_ESCAPE:
				_leave_to_menu()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_clear_selection()
			queue_redraw()


func _can_interact() -> bool:
	return _shop == null and not _ai_thinking and not _is_game_over() \
			and engine.turn == GameConfig.player_color


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
# Round flow
# =============================================================================

func _new_run() -> void:
	run = RunState.new()
	_start_round()


## Resets the board, applies owned upgrades / enemy queens, and begins play.
func _start_round() -> void:
	_round_token += 1
	_ai_thinking = false
	_clear_game_over()
	engine.reset()
	run.begin_round(engine, GameConfig.player_color)
	_round_enemy_material = RunState.material(engine.board, GameConfig.player_color, false)
	_round_settled = false
	_last_reward = {}
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
	var token := _round_token
	queue_redraw()

	await get_tree().create_timer(AI_THINK_DELAY).timeout
	# The round may have been reset or the scene left while we waited.
	if not is_inside_tree() or token != _round_token:
		return

	var move: Array = ai.choose_move(engine)
	_ai_thinking = false
	if move.size() == 2:
		_make_move(move[0], move[1])
	_clear_selection()
	queue_redraw()


func _undo() -> void:
	if _ai_thinking or _shop != null or _is_game_over() or engine.history.is_empty():
		return
	if run.undos_left <= 0:
		_toast("No undos left!")
		return
	run.undos_left -= 1

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


func _settle_round(won: bool) -> void:
	if _round_settled:
		return
	_round_settled = true
	_last_reward = run.settle_round(engine, GameConfig.player_color, _round_enemy_material, won)


func _check_game_state() -> void:
	if not _is_game_over():
		_clear_game_over()
		return
	if _game_over_layer != null or _defeat_pending:
		return

	if _status == ChessEngine.Status.STALEMATE:
		_settle_round(false)
		_show_draw_menu()
	elif engine.turn == GameConfig.player_color:
		if run.use_extra_life():
			_second_wind()
			return
		_settle_round(false)
		_show_lose_menu()
	else:
		_settle_round(true)
		_show_win_menu()


## Consumes a Second Wind: rewinds the last couple of moves instead of losing.
func _second_wind() -> void:
	var plies := 0
	while plies < SECOND_WIND_PLIES and not engine.history.is_empty():
		engine.undo()
		plies += 1
	while engine.turn != GameConfig.player_color and not engine.history.is_empty():
		engine.undo()
	_toast("Second Wind! The board rewinds.")
	_reset_view_state()
	_maybe_ai_move()


func _on_win_continue() -> void:
	run.advance_round(true)   # the opponent earns an extra queen
	_start_round()


func _on_draw_continue() -> void:
	_start_round()


func _on_lose_continue() -> void:
	_open_shop()


func _open_shop() -> void:
	_clear_game_over()
	_shop = ShopScreen.new()
	_shop.setup(run, _last_reward)
	_shop.next_round_requested.connect(_on_shop_closed)
	add_child(_shop)


func _on_shop_closed() -> void:
	if _shop != null:
		_shop.queue_free()
		_shop = null
	run.advance_round(false)
	_start_round()


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

func _show_win_menu() -> void:
	var vbox := _open_game_over_menu("Checkmate!", "You defeated the opponent.")
	_add_reward_label(vbox)
	vbox.add_child(_make_label("The opponent will gain an extra Queen.", 16, MOVE_CAPTURE))
	vbox.add_child(_make_button("Keep Playing", _on_win_continue))
	vbox.add_child(_make_button("Quit to Menu", _leave_to_menu))


func _show_draw_menu() -> void:
	var vbox := _open_game_over_menu("Draw", "The game ended in stalemate.")
	_add_reward_label(vbox)
	vbox.add_child(_make_button("Play Again", _on_draw_continue))
	vbox.add_child(_make_button("Quit to Menu", _leave_to_menu))


## Defeat: screen shake + red flash, then the menu slams in over falling pieces,
## with a heartbeat that slows down as the countdown runs out.
func _show_lose_menu() -> void:
	_defeat_pending = true
	_play_defeat_impact()

	var token := _round_token
	await get_tree().create_timer(DEFEAT_MENU_DELAY).timeout
	if token != _round_token or _leaving or not is_inside_tree():
		return
	_defeat_pending = false

	var vbox := _open_game_over_menu("You lose", "", true)

	_heart_piece = TextureRect.new()
	_heart_piece.texture = piece_textures[WHITE_KING_CODE]
	_heart_piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_heart_piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_heart_piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_heart_piece.custom_minimum_size = Vector2(120, 120)
	_heart_piece.pivot_offset = Vector2(60, 60)
	vbox.add_child(_heart_piece)

	_timer_label = _make_label(str(int(LOSE_COUNTDOWN)), 48, TEXT)
	_timer_label.pivot_offset = Vector2(30, 28)
	vbox.add_child(_timer_label)

	_add_reward_label(vbox)
	vbox.add_child(_make_button("Continue Playing", _on_lose_continue))
	vbox.add_child(_make_button("Quit", _leave_to_menu))

	_lose_timer = LOSE_COUNTDOWN
	_last_tick = int(LOSE_COUNTDOWN)
	_beat_phase = 0.0
	_crack_applied = false


func _play_defeat_impact() -> void:
	_shake_anim.start(DEFEAT_SHAKE_TIME)

	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 60
	add_child(flash_layer)
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.75, 0.12, 0.12, 0.55)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_layer.add_child(flash)

	var tween := flash.create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.7)
	tween.tween_callback(flash_layer.queue_free)


func _add_reward_label(vbox: VBoxContainer) -> void:
	var total := int(_last_reward.get("total", 0))
	if total > 0:
		vbox.add_child(_make_label("Earned $%d" % total, 20, GOLD))


## Builds the shared dim backdrop + centered panel and returns the panel's VBox.
func _open_game_over_menu(title_text: String, subtitle: String, lose_style: bool = false) -> VBoxContainer:
	_game_over_layer = CanvasLayer.new()
	add_child(_game_over_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(OVERLAY_DIM, 0.0)
	_game_over_layer.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", OVERLAY_DIM.a, 0.6)

	if lose_style:
		_spawn_falling_pieces()
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

	var title := _make_label(title_text, 38, ACCENT)
	vbox.add_child(title)
	if lose_style:
		# Letters appear one by one, like a verdict being read out.
		title.visible_ratio = 0.0
		var reveal := title.create_tween()
		reveal.tween_interval(0.25)
		reveal.tween_property(title, "visible_ratio", 1.0, 0.8)
	if subtitle != "":
		vbox.add_child(_make_label(subtitle, 18, TEXT))

	_animate_menu_popup(panel, lose_style)
	return vbox


## Faint chess pieces drifting down behind the defeat panel.
func _spawn_falling_pieces() -> void:
	var view := get_viewport().get_visible_rect().size
	var codes := [-1, -2, -3, -4, -5, -6, 1, 2, 3, 4, 5, 6]
	for i in range(FALLING_PIECE_COUNT):
		var texture: Texture2D = piece_textures.get(codes.pick_random())
		if texture == null:
			continue
		var size := randf_range(36.0, 72.0)
		var sprite := TextureRect.new()
		sprite.texture = texture
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.custom_minimum_size = Vector2(size, size)
		sprite.size = Vector2(size, size)
		sprite.pivot_offset = Vector2(size, size) / 2.0
		sprite.modulate = Color(1, 1, 1, randf_range(0.12, 0.3))
		sprite.position = Vector2(randf_range(0.0, view.x), randf_range(-view.y, 0.0))
		var start_rotation := randf_range(-0.6, 0.6)
		sprite.rotation = start_rotation
		_game_over_layer.add_child(sprite)

		var duration := randf_range(4.0, 8.0)
		var fall := sprite.create_tween().set_loops()
		fall.tween_property(sprite, "position:y", view.y + 80.0, duration).from(-100.0)
		var spin := sprite.create_tween().set_loops()
		spin.tween_property(sprite, "rotation", start_rotation + randf_range(-2.0, 2.0), duration).from(start_rotation)


func _clear_game_over() -> void:
	if _game_over_layer != null:
		_game_over_layer.queue_free()
		_game_over_layer = null

	_defeat_pending = false
	_heart_piece = null
	_timer_label = null
	_fade_overlay = null
	_lose_timer = 0.0


func _animate_menu_popup(target: Control, slam: bool = false) -> void:
	target.scale = Vector2(1.6, 1.6) if slam else Vector2(0.6, 0.6)
	target.modulate.a = 0.0

	# Container sizes are only known after the first layout pass.
	await get_tree().process_frame
	if not is_instance_valid(target):
		return
	target.pivot_offset = target.size / 2.0

	var tween := target.create_tween().set_parallel(true)
	if slam:
		tween.tween_property(target, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(target, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _punch(control: Control, amount: float) -> void:
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2.ONE * amount
	control.create_tween().tween_property(control, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
