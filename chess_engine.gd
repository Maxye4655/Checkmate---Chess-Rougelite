class_name ChessEngine
extends RefCounted


enum Type { EMPTY = 0, PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6 }
enum Status { PLAYING, CHECK, CHECKMATE, STALEMATE }

const WHITE := 1
const BLACK := -1

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
			return _jump_moves(from, color, KING_OFFSETS)
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
	return moves


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


func _apply_to_board(b: Array, from: Vector2i, to: Vector2i) -> void:
	var code: int = b[from.y][from.x]
	b[from.y][from.x] = Type.EMPTY
	if type_of(code) == Type.PAWN and (to.y == 0 or to.y == 7):
		code = Type.QUEEN * color_of(code)
	b[to.y][to.x] = code


func make_move(from: Vector2i, to: Vector2i) -> bool:
	if color_of(piece_at(from)) != turn:
		return false
	if not (to in pseudo_moves(from)) or not _is_legal(from, to):
		return false
	history.append({"board": board.duplicate(true), "turn": turn, "last": last_move.duplicate()})
	_apply_to_board(board, from, to)
	last_move = [from, to]
	turn = -turn
	return true


func undo() -> bool:
	if history.is_empty():
		return false
	var snapshot: Dictionary = history.pop_back()
	board = snapshot["board"]
	turn = snapshot["turn"]
	last_move = snapshot["last"]
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
