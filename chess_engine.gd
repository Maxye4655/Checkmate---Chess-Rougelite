class_name ChessEngine
extends RefCounted


enum Type { EMPTY = 0, PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6 }
enum Status { PLAYING, CHECK, CHECKMATE, STALEMATE }

const WHITE := 1
const BLACK := -1

# Castling rights are a bitmask: which castles are still allowed (king and rook unmoved).
const CASTLE_WK := 1   # White, king side  (e1 -> g1)
const CASTLE_WQ := 2   # White, queen side (e1 -> c1)
const CASTLE_BK := 4   # Black, king side  (e8 -> g8)
const CASTLE_BQ := 8   # Black, queen side (e8 -> c8)

const KNIGHT_OFFSETS := [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2),
]
const KING_OFFSETS := [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]
const DIAGONALS := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const ORTHOGONALS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var board: Array = []
var turn: int = WHITE
var last_move: Array = []
var history: Array = []
var castle_rights: int = 15                 # all four castles available at the start
var ep_square := Vector2i(-1, -1)           # square a pawn just skipped over (en passant target)


func _init() -> void:
	reset()


func reset() -> void:
	board = []
	for r in range(8):
		board.append([0, 0, 0, 0, 0, 0, 0, 0])
	var back_rank := [Type.ROOK, Type.KNIGHT, Type.BISHOP, Type.QUEEN, Type.KING, Type.BISHOP, Type.KNIGHT, Type.ROOK]
	for c in range(8):
		board[0][c] = -back_rank[c]
		board[1][c] = -Type.PAWN
		board[6][c] = Type.PAWN
		board[7][c] = back_rank[c]
	turn = WHITE
	last_move = []
	history = []
	castle_rights = 15
	ep_square = Vector2i(-1, -1)


static func color_of(code: int) -> int:
	return signi(code)


static func type_of(code: int) -> int:
	return absi(code)


func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < 8 and pos.y >= 0 and pos.y < 8


func piece_at(pos: Vector2i) -> int:
	if not in_bounds(pos):
		return 0
	return board[pos.y][pos.x]


func find_king(b: Array, color: int) -> Vector2i:
	for r in range(8):
		for c in range(8):
			if b[r][c] == Type.KING * color:
				return Vector2i(c, r)
	return Vector2i(-1, -1)


func in_check(color: int) -> bool:
	return _in_check(board, color)


func _in_check(b: Array, color: int) -> bool:
	var king := find_king(b, color)
	if king == Vector2i(-1, -1):
		return false
	return _is_attacked(b, king, -color)


func _is_attacked(b: Array, square: Vector2i, by_color: int) -> bool:
	var pawn_dir := -1 if by_color == WHITE else 1
	for dx in [-1, 1]:
		var p: Vector2i = square + Vector2i(dx, -pawn_dir)
		if in_bounds(p) and b[p.y][p.x] == Type.PAWN * by_color:
			return true
	for off in KNIGHT_OFFSETS:
		var p: Vector2i = square + off
		if in_bounds(p) and b[p.y][p.x] == Type.KNIGHT * by_color:
			return true
	for off in KING_OFFSETS:
		var p: Vector2i = square + off
		if in_bounds(p) and b[p.y][p.x] == Type.KING * by_color:
			return true
	for dir in DIAGONALS:
		if _ray_attacked(b, square, dir, Type.BISHOP, by_color):
			return true
	for dir in ORTHOGONALS:
		if _ray_attacked(b, square, dir, Type.ROOK, by_color):
			return true
	return false


func _ray_attacked(b: Array, square: Vector2i, dir: Vector2i, slider: int, by_color: int) -> bool:
	var p := square + dir
	while in_bounds(p):
		var code: int = b[p.y][p.x]
		if code != Type.EMPTY:
			if color_of(code) == by_color and (type_of(code) == slider or type_of(code) == Type.QUEEN):
				return true
			return false
		p += dir
	return false


func pseudo_moves(from: Vector2i) -> Array:
	var code := piece_at(from)
	if code == Type.EMPTY:
		return []
	var color := color_of(code)
	match type_of(code):
		Type.PAWN:
			return _pawn_moves(from, color)
		Type.KNIGHT:
			return _jump_moves(from, color, KNIGHT_OFFSETS)
		Type.BISHOP:
			return _slide_moves(from, color, DIAGONALS)
		Type.ROOK:
			return _slide_moves(from, color, ORTHOGONALS)
		Type.QUEEN:
			return _slide_moves(from, color, DIAGONALS + ORTHOGONALS)
		Type.KING:
			return _jump_moves(from, color, KING_OFFSETS) + _castling_moves(from, color)
	return []


func _jump_moves(from: Vector2i, color: int, offsets: Array) -> Array:
	var moves := []
	for off in offsets:
		var to: Vector2i = from + off
		if in_bounds(to) and color_of(piece_at(to)) != color:
			moves.append(to)
	return moves


func _slide_moves(from: Vector2i, color: int, dirs: Array) -> Array:
	var moves := []
	for dir in dirs:
		var to: Vector2i = from + dir
		while in_bounds(to):
			var code := piece_at(to)
			if code == Type.EMPTY:
				moves.append(to)
			else:
				if color_of(code) != color:
					moves.append(to)
				break
			to += dir
	return moves


func _pawn_moves(from: Vector2i, color: int) -> Array:
	var moves := []
	var dir := -1 if color == WHITE else 1
	var start_row := 6 if color == WHITE else 1
	var one := from + Vector2i(0, dir)
	if in_bounds(one) and piece_at(one) == Type.EMPTY:
		moves.append(one)
		var two := from + Vector2i(0, dir * 2)
		if from.y == start_row and piece_at(two) == Type.EMPTY:
			moves.append(two)
	for dx in [-1, 1]:
		var to := from + Vector2i(dx, dir)
		if in_bounds(to):
			var code := piece_at(to)
			if code != Type.EMPTY and color_of(code) != color:
				moves.append(to)
			elif to == ep_square and piece_at(Vector2i(to.x, from.y)) == -color * Type.PAWN:
				moves.append(to)   # en passant: the enemy pawn that just double-stepped beside us
	return moves


## Castling destinations for a king (the king moves two squares; the rook follows).
## Needs: rights intact, king and rook on their home squares, empty squares between,
## king not in check and not passing through an attacked square. (Landing on an
## attacked square is rejected later by _is_legal, like any other king move.)
func _castling_moves(from: Vector2i, color: int) -> Array:
	var moves := []
	var row := 7 if color == WHITE else 0
	if from != Vector2i(4, row) or piece_at(from) != Type.KING * color:
		return moves
	var king_bit := CASTLE_WK if color == WHITE else CASTLE_BK
	var queen_bit := CASTLE_WQ if color == WHITE else CASTLE_BQ
	if (castle_rights & (king_bit | queen_bit)) == 0:
		return moves
	if _is_attacked(board, from, -color):
		return moves   # can't castle out of check

	var rook := Type.ROOK * color
	if (castle_rights & king_bit) != 0 and piece_at(Vector2i(7, row)) == rook \
			and piece_at(Vector2i(5, row)) == Type.EMPTY and piece_at(Vector2i(6, row)) == Type.EMPTY \
			and not _is_attacked(board, Vector2i(5, row), -color):
		moves.append(Vector2i(6, row))
	if (castle_rights & queen_bit) != 0 and piece_at(Vector2i(0, row)) == rook \
			and piece_at(Vector2i(1, row)) == Type.EMPTY and piece_at(Vector2i(2, row)) == Type.EMPTY \
			and piece_at(Vector2i(3, row)) == Type.EMPTY \
			and not _is_attacked(board, Vector2i(3, row), -color):
		moves.append(Vector2i(2, row))
	return moves


## True if moving from -> to would be a castling move (the king steps two files).
func is_castling(from: Vector2i, to: Vector2i) -> bool:
	return type_of(piece_at(from)) == Type.KING and absi(to.x - from.x) == 2


## True if from -> to would capture en passant.
func is_en_passant(from: Vector2i, to: Vector2i) -> bool:
	return type_of(piece_at(from)) == Type.PAWN and from.x != to.x and to == ep_square


func legal_moves(from: Vector2i) -> Array:
	var code := piece_at(from)
	if code == Type.EMPTY or color_of(code) != turn:
		return []
	var result := []
	for to in pseudo_moves(from):
		if _is_legal(from, to):
			result.append(to)
	return result


func _is_legal(from: Vector2i, to: Vector2i) -> bool:
	var moving := piece_at(from)
	if moving == Type.EMPTY:
		return false
	var test := board.duplicate(true)
	_apply_to_board(test, from, to)
	return not _in_check(test, color_of(moving))


## Plays from -> to on board `b` (a real board or a scratch copy). Handles the extra
## things a move can do: promote to a queen, remove a pawn taken en passant, and move
## the rook when castling.
func _apply_to_board(b: Array, from: Vector2i, to: Vector2i) -> void:
	var code: int = b[from.y][from.x]
	b[from.y][from.x] = Type.EMPTY
	if type_of(code) == Type.PAWN:
		if from.x != to.x and b[to.y][to.x] == Type.EMPTY:
			b[from.y][to.x] = Type.EMPTY   # en passant: the captured pawn sits beside the start square
		elif to.y == 0 or to.y == 7:
			code = Type.QUEEN * color_of(code)
	elif type_of(code) == Type.KING and absi(to.x - from.x) == 2:
		var rook_from := 7 if to.x > from.x else 0
		var rook_to := 5 if to.x > from.x else 3
		b[from.y][rook_to] = b[from.y][rook_from]
		b[from.y][rook_from] = Type.EMPTY
	b[to.y][to.x] = code


func make_move(from: Vector2i, to: Vector2i) -> bool:
	if color_of(piece_at(from)) != turn:
		return false
	if not (to in pseudo_moves(from)) or not _is_legal(from, to):
		return false
	history.append({
		"board": board.duplicate(true), "turn": turn, "last": last_move.duplicate(),
		"castle": castle_rights, "ep": ep_square,
	})

	var moving := piece_at(from)

	# A double pawn step makes the skipped square capturable en passant for one turn.
	var new_ep := Vector2i(-1, -1)
	if type_of(moving) == Type.PAWN and absi(to.y - from.y) == 2:
		new_ep = Vector2i(from.x, from.y + signi(to.y - from.y))

	# Rights are lost when the king moves, or a rook moves from / is captured on its corner.
	castle_rights &= ~(_corner_bits(from) | _corner_bits(to))
	if type_of(moving) == Type.KING:
		var both := (CASTLE_WK | CASTLE_WQ) if color_of(moving) == WHITE else (CASTLE_BK | CASTLE_BQ)
		castle_rights &= ~both

	_apply_to_board(board, from, to)   # uses the OLD ep_square, so assign the new one after
	ep_square = new_ep
	last_move = [from, to]
	turn = -turn
	return true


static func _corner_bits(square: Vector2i) -> int:
	if square == Vector2i(7, 7):
		return CASTLE_WK
	if square == Vector2i(0, 7):
		return CASTLE_WQ
	if square == Vector2i(7, 0):
		return CASTLE_BK
	if square == Vector2i(0, 0):
		return CASTLE_BQ
	return 0


func undo() -> bool:
	if history.is_empty():
		return false
	var snapshot: Dictionary = history.pop_back()
	board = snapshot["board"]
	turn = snapshot["turn"]
	last_move = snapshot["last"]
	castle_rights = snapshot.get("castle", 15)
	ep_square = snapshot.get("ep", Vector2i(-1, -1))
	return true


func _has_legal_move(color: int) -> bool:
	for r in range(8):
		for c in range(8):
			if color_of(board[r][c]) != color:
				continue
			var from := Vector2i(c, r)
			for to in pseudo_moves(from):
				if _is_legal(from, to):
					return true
	return false


func status() -> Status:
	if not _has_legal_move(turn):
		return Status.CHECKMATE if in_check(turn) else Status.STALEMATE
	if in_check(turn):
		return Status.CHECK
	return Status.PLAYING
