class_name ChessAI
extends RefCounted


const WHITE := 1
const BLACK := -1
const EMPTY := 0

const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6

const MATE := 100000
const INF := 1 << 29
const MAX_PLY := 64

const TIME_MS := 1200

const TT_EXACT := 0
const TT_LOWER := 1
const TT_UPPER := 2

const DIR_DR := [1, -1, 0, 0, 1, 1, -1, -1]
const DIR_DC := [0, 0, 1, -1, 1, -1, 1, -1]

const PIECE_VALUE := [0, 100, 320, 330, 500, 900, 20000]

const PST_PAWN := [
	[0, 0, 0, 0, 0, 0, 0, 0],
	[50, 50, 50, 50, 50, 50, 50, 50],
	[10, 10, 20, 30, 30, 20, 10, 10],
	[5, 5, 10, 25, 25, 10, 5, 5],
	[0, 0, 0, 20, 20, 0, 0, 0],
	[5, -5, -10, 0, 0, -10, -5, 5],
	[5, 10, 10, -20, -20, 10, 10, 5],
	[0, 0, 0, 0, 0, 0, 0, 0],
]
const PST_KNIGHT := [
	[-50, -40, -30, -30, -30, -30, -40, -50],
	[-40, -20, 0, 0, 0, 0, -20, -40],
	[-30, 0, 10, 15, 15, 10, 0, -30],
	[-30, 5, 15, 20, 20, 15, 5, -30],
	[-30, 0, 15, 20, 20, 15, 0, -30],
	[-30, 5, 10, 15, 15, 10, 5, -30],
	[-40, -20, 0, 5, 5, 0, -20, -40],
	[-50, -40, -30, -30, -30, -30, -40, -50],
]
const PST_BISHOP := [
	[-20, -10, -10, -10, -10, -10, -10, -20],
	[-10, 0, 0, 0, 0, 0, 0, -10],
	[-10, 0, 5, 10, 10, 5, 0, -10],
	[-10, 5, 5, 10, 10, 5, 5, -10],
	[-10, 0, 10, 10, 10, 10, 0, -10],
	[-10, 10, 10, 10, 10, 10, 10, -10],
	[-10, 5, 0, 0, 0, 0, 5, -10],
	[-20, -10, -10, -10, -10, -10, -10, -20],
]
const PST_ROOK := [
	[0, 0, 0, 0, 0, 0, 0, 0],
	[5, 10, 10, 10, 10, 10, 10, 5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[0, 0, 0, 5, 5, 0, 0, 0],
]
const PST_QUEEN := [
	[-20, -10, -10, -5, -5, -10, -10, -20],
	[-10, 0, 0, 0, 0, 0, 0, -10],
	[-10, 0, 5, 5, 5, 5, 0, -10],
	[-5, 0, 5, 5, 5, 5, 0, -5],
	[0, 0, 5, 5, 5, 5, 0, -5],
	[-10, 5, 5, 5, 5, 5, 0, -10],
	[-10, 0, 5, 0, 0, 0, 0, -10],
	[-20, -10, -10, -5, -5, -10, -10, -20],
]
const PST_KING := [
	[-30, -40, -40, -50, -50, -40, -40, -30],
	[-30, -40, -40, -50, -50, -40, -40, -30],
	[-30, -40, -40, -50, -50, -40, -40, -30],
	[-30, -40, -40, -50, -50, -40, -40, -30],
	[-20, -30, -30, -40, -40, -30, -30, -20],
	[-10, -20, -20, -20, -20, -20, -20, -10],
	[20, 20, 0, 0, 0, 0, 20, 20],
	[20, 30, 10, 0, 0, 10, 30, 20],
]

var _board := PackedInt32Array()
var _side := WHITE
var _rows := PackedInt32Array()
var _cols := PackedInt32Array()
var _knight_targets := []
var _king_targets := []
var _king_sq := {}

var _hash := 0
var _z_piece := []
var _z_side := 0
var _z_castle := []        # one key per castling-rights bitmask (0..15)
var _z_ep := []            # one key per en passant file

var _castle := 0           # castling rights, same bitmask as ChessEngine.castle_rights
var _ep := -1              # en passant target square (0..63), or -1

var _deadline := 0
var _stop := false
var _nodes := 0
var _tt := {}
var _killers := []
var _history := {}


func _init() -> void:
	_precompute()
	_init_zobrist()


func choose_move(engine: ChessEngine) -> Array:
	_load(engine)
	_tt.clear()
	_history.clear()
	_killers = []
	for i in range(MAX_PLY + 2):
		_killers.append([-1, -1])
	_stop = false
	_nodes = 0
	_deadline = Time.get_ticks_msec() + TIME_MS

	var best_move := 0
	for depth in range(1, MAX_PLY):
		var result := _root(depth, best_move)
		if _stop and best_move != 0:
			break
		if int(result[0]) != 0:
			best_move = int(result[0])
		if absi(int(result[1])) > MATE - 1000:
			break
		if _stop:
			break

	if best_move == 0 or not _is_move_legal_in_engine(engine, best_move):
		best_move = _first_legal_encoded(engine)
	if best_move == 0:
		return []
	return [_decode(best_move >> 6), _decode(best_move & 63)]


func _decode(sq: int) -> Vector2i:
	return Vector2i(sq & 7, sq >> 3)


func _is_move_legal_in_engine(engine: ChessEngine, move: int) -> bool:
	var from := _decode(move >> 6)
	var to := _decode(move & 63)
	return to in engine.legal_moves(from)


func _first_legal_encoded(engine: ChessEngine) -> int:
	for r in range(8):
		for c in range(8):
			var code: int = engine.board[r][c]
			if code == EMPTY or ChessEngine.color_of(code) != engine.turn:
				continue
			var from := Vector2i(c, r)
			for to in engine.legal_moves(from):
				return (r * 8 + c) * 64 + (to.y * 8 + to.x)
	return 0


func _root(depth: int, pv_move: int) -> Array:
	var alpha := -INF
	var best := 0
	var best_score := -INF
	var moves := _gen_legal(_side)
	if moves.is_empty():
		return [0, 0]
	_order(moves, pv_move, 0)
	for m in moves:
		var undo := _make(m)
		var score := -_search(depth - 1, -INF, -alpha, 1)
		_unmake(m, undo)
		if _stop:
			return [best, best_score if best_score != -INF else 0]
		if score > best_score:
			best_score = score
			best = m
		if score > alpha:
			alpha = score
	return [best, best_score]


func _search(depth: int, alpha: int, beta: int, ply: int) -> int:
	if (_nodes & 1023) == 0 and Time.get_ticks_msec() >= _deadline:
		_stop = true
		return 0
	_nodes += 1
	if ply >= MAX_PLY:
		return _eval() * _side

	var key := _hash
	var stored: int = _tt.get(key, 0)
	var tt_move := 0
	if stored != 0:
		tt_move = stored & 0xFFF
		var tt_depth := (stored >> 12) & 0xFF
		var tt_flag := (stored >> 20) & 0x3
		var tt_score := ((stored >> 22) & 0xFFFFFFFF) - (1 << 31)
		if tt_depth >= depth:
			if tt_flag == TT_EXACT:
				return tt_score
			elif tt_flag == TT_LOWER:
				if tt_score > alpha:
					alpha = tt_score
			else:
				if tt_score < beta:
					beta = tt_score
			if alpha >= beta:
				return tt_score

	var in_check := _in_check(_side)
	if depth <= 0:
		if not in_check:
			return _quiesce(alpha, beta, ply)
		depth = 1

	var moves := _gen_legal(_side)
	if moves.is_empty():
		return (-MATE + ply) if in_check else 0

	_order(moves, tt_move, ply)
	var best := -INF
	var best_move := 0
	var orig_alpha := alpha
	for m in moves:
		var undo := _make(m)
		var score := -_search(depth - 1, -beta, -alpha, ply + 1)
		_unmake(m, undo)
		if _stop:
			return 0
		if score > best:
			best = score
			best_move = m
		if best > alpha:
			alpha = best
		if alpha >= beta:
			if _board_is_quiet(m):
				_record_killer(ply, m)
			break

	var flag := TT_EXACT
	if best <= orig_alpha:
		flag = TT_UPPER
	elif best >= beta:
		flag = TT_LOWER
	_tt_store(key, depth, best, flag, best_move)
	return best


func _quiesce(alpha: int, beta: int, ply: int) -> int:
	if (_nodes & 1023) == 0 and Time.get_ticks_msec() >= _deadline:
		_stop = true
		return 0
	_nodes += 1
	if ply >= MAX_PLY:
		return _eval() * _side

	var in_check := _in_check(_side)
	if not in_check:
		var stand := _eval() * _side
		if stand >= beta:
			return beta
		if stand > alpha:
			alpha = stand

	var moves := _gen_legal(_side) if in_check else _gen_captures(_side)
	if in_check and moves.is_empty():
		return -MATE + ply
	_order(moves, 0, ply)
	for m in moves:
		var undo := _make(m)
		var score := -_quiesce(-beta, -alpha, ply + 1)
		_unmake(m, undo)
		if _stop:
			return 0
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
	return alpha


func _record_killer(ply: int, move: int) -> void:
	if ply >= _killers.size():
		return
	if _killers[ply][0] != move:
		_killers[ply][1] = _killers[ply][0]
		_killers[ply][0] = move


func _board_is_quiet(move: int) -> bool:
	return _board[move & 63] == EMPTY


func _gen_pseudo(side: int, captures_only: bool) -> Array:
	var moves := []
	for sq in range(64):
		var code := _board[sq]
		if code == EMPTY or signi(code) != side:
			continue
		var t := absi(code)
		match t:
			PAWN:
				_pawn_moves(sq, side, captures_only, moves)
			KNIGHT:
				for to in _knight_targets[sq]:
					var target := _board[to]
					if target == EMPTY:
						if not captures_only:
							moves.append(sq * 64 + to)
					elif signi(target) != side:
						moves.append(sq * 64 + to)
			BISHOP:
				_slide(sq, side, 4, 8, captures_only, moves)   # all four diagonals
			ROOK:
				_slide(sq, side, 0, 4, captures_only, moves)   # all four straight lines
			QUEEN:
				_slide(sq, side, 0, 8, captures_only, moves)
			KING:
				for to in _king_targets[sq]:
					var target := _board[to]
					if target == EMPTY:
						if not captures_only:
							moves.append(sq * 64 + to)
					elif signi(target) != side:
						moves.append(sq * 64 + to)
				if not captures_only:
					_castle_moves(sq, side, moves)
	return moves


## Castling: the king moves two squares (the rook is moved in _make). Same rules as
## ChessEngine; landing on an attacked square is rejected by _gen_legal.
func _castle_moves(sq: int, side: int, moves: Array) -> void:
	var king_bit := 1 if side == WHITE else 4
	var queen_bit := 2 if side == WHITE else 8
	if (_castle & (king_bit | queen_bit)) == 0:
		return
	var home := 60 if side == WHITE else 4   # e1 / e8
	if sq != home or _is_attacked(sq, -side):
		return
	var rook := ROOK * side
	if (_castle & king_bit) != 0 and _board[sq + 3] == rook \
			and _board[sq + 1] == EMPTY and _board[sq + 2] == EMPTY \
			and not _is_attacked(sq + 1, -side):
		moves.append(sq * 64 + sq + 2)
	if (_castle & queen_bit) != 0 and _board[sq - 4] == rook \
			and _board[sq - 1] == EMPTY and _board[sq - 2] == EMPTY and _board[sq - 3] == EMPTY \
			and not _is_attacked(sq - 1, -side):
		moves.append(sq * 64 + sq - 2)


func _slide(sq: int, side: int, d0: int, d1: int, captures_only: bool, moves: Array) -> void:
	for d in range(d0, d1):
		var r: int = _rows[sq] + DIR_DR[d]
		var c: int = _cols[sq] + DIR_DC[d]
		while r >= 0 and r < 8 and c >= 0 and c < 8:
			var to := r * 8 + c
			var target := _board[to]
			if target == EMPTY:
				if not captures_only:
					moves.append(sq * 64 + to)
			else:
				if signi(target) != side:
					moves.append(sq * 64 + to)
				break
			r += DIR_DR[d]
			c += DIR_DC[d]


func _pawn_moves(sq: int, side: int, captures_only: bool, moves: Array) -> void:
	var r := _rows[sq]
	var c := _cols[sq]
	var dir := -1 if side == WHITE else 1
	var start_row := 6 if side == WHITE else 1
	var last_row := 0 if side == WHITE else 7
	var fr := r + dir
	if fr >= 0 and fr < 8:
		var one := fr * 8 + c
		if _board[one] == EMPTY:
			if not captures_only:
				moves.append(sq * 64 + one)
				if r == start_row:
					var two := (r + dir * 2) * 8 + c
					if _board[two] == EMPTY:
						moves.append(sq * 64 + two)
			elif fr == last_row:
				moves.append(sq * 64 + one)
		for dc in [-1, 1]:
			var tc: int = c + dc
			if tc >= 0 and tc < 8:
				var to := fr * 8 + tc
				var target := _board[to]
				if target != EMPTY and signi(target) != side:
					moves.append(sq * 64 + to)
				elif to == _ep and target == EMPTY and _board[r * 8 + tc] == -PAWN * side:
					moves.append(sq * 64 + to)   # en passant


func _gen_captures(side: int) -> Array:
	return _gen_pseudo(side, true)


func _gen_legal(side: int) -> Array:
	var legal := []
	for m in _gen_pseudo(side, false):
		var undo := _make(m)
		if not _in_check(side):
			legal.append(m)
		_unmake(m, undo)
	return legal


func _make(move: int) -> int:
	var from := move >> 6
	var to := move & 63
	var moved := _board[from]
	var captured := _board[to]
	var prev_castle := _castle
	var prev_ep := _ep
	var t := absi(moved)
	_board[from] = EMPTY
	var placed := moved
	var new_ep := -1

	if t == PAWN:
		var to_row := to >> 3
		if to_row == 0 or to_row == 7:
			placed = QUEEN * signi(moved)
		elif captured == EMPTY and (to & 7) != (from & 7):
			# en passant: remove the pawn beside the start square
			var cap_sq := (from & ~7) + (to & 7)
			_hash ^= _z_piece[_piece_index(_board[cap_sq])][cap_sq]
			_board[cap_sq] = EMPTY
		elif absi(to - from) == 16:
			new_ep = (from + to) >> 1
	elif t == KING and absi(to - from) == 2:
		# castling: move the rook too
		var rook_from := from + 3 if to > from else from - 4
		var rook_to := from + 1 if to > from else from - 1
		var rook := _board[rook_from]
		_board[rook_from] = EMPTY
		_board[rook_to] = rook
		_hash ^= _z_piece[_piece_index(rook)][rook_from]
		_hash ^= _z_piece[_piece_index(rook)][rook_to]

	_board[to] = placed

	_hash ^= _z_piece[_piece_index(moved)][from]
	if captured != EMPTY:
		_hash ^= _z_piece[_piece_index(captured)][to]
	_hash ^= _z_piece[_piece_index(placed)][to]
	_hash ^= _z_side

	if moved == KING:
		_king_sq[WHITE] = to
	elif moved == -KING:
		_king_sq[BLACK] = to

	# Castling rights: lost when the king moves or a rook moves from / is taken on its corner.
	_castle &= ~(_corner_bits(from) | _corner_bits(to))
	if moved == KING:
		_castle &= ~3
	elif moved == -KING:
		_castle &= ~12
	_hash ^= _z_castle[prev_castle] ^ _z_castle[_castle]
	if prev_ep >= 0:
		_hash ^= _z_ep[prev_ep & 7]
	if new_ep >= 0:
		_hash ^= _z_ep[new_ep & 7]
	_ep = new_ep

	_side = -_side
	return (moved + 8) | ((captured + 8) << 8) | (prev_castle << 16) | ((prev_ep + 1) << 20)


func _unmake(move: int, undo: int) -> void:
	var from := move >> 6
	var to := move & 63
	var moved := (undo & 0xFF) - 8
	var captured := ((undo >> 8) & 0xFF) - 8
	var prev_castle := (undo >> 16) & 0xF
	var prev_ep := ((undo >> 20) & 0x7F) - 1
	var placed := _board[to]
	var t := absi(moved)

	_board[from] = moved
	_board[to] = captured

	_hash ^= _z_piece[_piece_index(moved)][from]
	if captured != EMPTY:
		_hash ^= _z_piece[_piece_index(captured)][to]
	_hash ^= _z_piece[_piece_index(placed)][to]
	_hash ^= _z_side

	if t == PAWN and captured == EMPTY and (to & 7) != (from & 7):
		# undo en passant: put the captured pawn back beside the start square
		var cap_sq := (from & ~7) + (to & 7)
		var cap_piece := -PAWN * signi(moved)
		_board[cap_sq] = cap_piece
		_hash ^= _z_piece[_piece_index(cap_piece)][cap_sq]
	elif t == KING and absi(to - from) == 2:
		# undo castling: put the rook back
		var rook_from := from + 3 if to > from else from - 4
		var rook_to := from + 1 if to > from else from - 1
		var rook := _board[rook_to]
		_board[rook_to] = EMPTY
		_board[rook_from] = rook
		_hash ^= _z_piece[_piece_index(rook)][rook_from]
		_hash ^= _z_piece[_piece_index(rook)][rook_to]

	if moved == KING:
		_king_sq[WHITE] = from
	elif moved == -KING:
		_king_sq[BLACK] = from

	_hash ^= _z_castle[_castle] ^ _z_castle[prev_castle]
	if _ep >= 0:
		_hash ^= _z_ep[_ep & 7]
	if prev_ep >= 0:
		_hash ^= _z_ep[prev_ep & 7]
	_castle = prev_castle
	_ep = prev_ep

	_side = -_side


## Castling-right bits lost when something moves from or to this square.
func _corner_bits(sq: int) -> int:
	match sq:
		63:
			return 1    # h1: White king side
		56:
			return 2    # a1: White queen side
		7:
			return 4    # h8: Black king side
		0:
			return 8    # a8: Black queen side
	return 0


func _in_check(color: int) -> bool:
	var k: int = _king_sq[color]
	if k < 0:
		return false
	return _is_attacked(k, -color)


func _is_attacked(sq: int, by: int) -> bool:
	var r := _rows[sq]
	var c := _cols[sq]

	var pr := r + 1 if by == WHITE else r - 1
	if pr >= 0 and pr < 8:
		for dc in [-1, 1]:
			var pc: int = c + dc
			if pc >= 0 and pc < 8 and _board[pr * 8 + pc] == PAWN * by:
				return true

	for to in _knight_targets[sq]:
		if _board[to] == KNIGHT * by:
			return true

	for to in _king_targets[sq]:
		if _board[to] == KING * by:
			return true

	for d in range(4, 8):
		var rr: int = r + DIR_DR[d]
		var cc: int = c + DIR_DC[d]
		while rr >= 0 and rr < 8 and cc >= 0 and cc < 8:
			var code := _board[rr * 8 + cc]
			if code != EMPTY:
				if signi(code) == by and (absi(code) == BISHOP or absi(code) == QUEEN):
					return true
				break
			rr += DIR_DR[d]
			cc += DIR_DC[d]

	for d in range(0, 4):
		var rr: int = r + DIR_DR[d]
		var cc: int = c + DIR_DC[d]
		while rr >= 0 and rr < 8 and cc >= 0 and cc < 8:
			var code := _board[rr * 8 + cc]
			if code != EMPTY:
				if signi(code) == by and (absi(code) == ROOK or absi(code) == QUEEN):
					return true
				break
			rr += DIR_DR[d]
			cc += DIR_DC[d]

	return false


func _eval() -> int:
	var score := 0
	var bishops_w := 0
	var bishops_b := 0
	var pawn_files_w := [0, 0, 0, 0, 0, 0, 0, 0]
	var pawn_files_b := [0, 0, 0, 0, 0, 0, 0, 0]
	var rook_files_w := [0, 0, 0, 0, 0, 0, 0, 0]
	var rook_files_b := [0, 0, 0, 0, 0, 0, 0, 0]

	for sq in range(64):
		var code := _board[sq]
		if code == EMPTY:
			continue
		var white := code > 0
		var t := absi(code)
		var v: int = PIECE_VALUE[t] + _pst(t, sq, white)
		var c := sq & 7
		if white:
			score += v
			if t == BISHOP:
				bishops_w += 1
			elif t == PAWN:
				pawn_files_w[c] += 1
			elif t == ROOK:
				rook_files_w[c] += 1
		else:
			score -= v
			if t == BISHOP:
				bishops_b += 1
			elif t == PAWN:
				pawn_files_b[c] += 1
			elif t == ROOK:
				rook_files_b[c] += 1

	if bishops_w >= 2:
		score += 30
	if bishops_b >= 2:
		score -= 30

	score += _pawn_structure(pawn_files_w, pawn_files_b)
	score -= _pawn_structure(pawn_files_b, pawn_files_w)
	score += _rook_files(rook_files_w, pawn_files_w, pawn_files_b)
	score -= _rook_files(rook_files_b, pawn_files_b, pawn_files_w)
	return score


func _pawn_structure(own: Array, enemy: Array) -> int:
	var s := 0
	for f in range(8):
		if own[f] == 0:
			continue
		if own[f] > 1:
			s -= (own[f] - 1) * 15
		var left: int = own[f - 1] if f > 0 else 0
		var right: int = own[f + 1] if f < 7 else 0
		if left == 0 and right == 0:
			s -= 15
	return s


func _rook_files(rooks: Array, own_pawns: Array, enemy_pawns: Array) -> int:
	var s := 0
	for f in range(8):
		if rooks[f] == 0:
			continue
		if own_pawns[f] == 0 and enemy_pawns[f] == 0:
			s += 15 * rooks[f]
		elif own_pawns[f] == 0:
			s += 8 * rooks[f]
	return s


func _pst(type: int, sq: int, white: bool) -> int:
	var row := sq >> 3
	var col := sq & 7
	if not white:
		row = 7 - row
	match type:
		PAWN:
			return PST_PAWN[row][col]
		KNIGHT:
			return PST_KNIGHT[row][col]
		BISHOP:
			return PST_BISHOP[row][col]
		ROOK:
			return PST_ROOK[row][col]
		QUEEN:
			return PST_QUEEN[row][col]
		KING:
			return PST_KING[row][col]
	return 0


## Scores every move once, then sorts. (Sorting with a comparator that rescored both
## moves on every comparison was the search's biggest cost.)
func _order(moves: Array, tt_move: int, ply: int) -> void:
	var scored := []
	for m in moves:
		scored.append([_score_move(m, tt_move, ply), m])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	for i in range(moves.size()):
		moves[i] = scored[i][1]


func _score_move(move: int, tt_move: int, ply: int) -> int:
	if move == tt_move:
		return 1 << 20
	var victim := _board[move & 63]
	if victim != EMPTY:
		var attacker := _board[move >> 6]
		return (1 << 15) + PIECE_VALUE[absi(victim)] * 16 - PIECE_VALUE[absi(attacker)]
	if ply < _killers.size():
		if move == _killers[ply][0]:
			return 1 << 14
		if move == _killers[ply][1]:
			return 1 << 13
	return _history.get(move, 0)


func _tt_store(key: int, depth: int, score: int, flag: int, move: int) -> void:
	if _tt.size() > 400000:
		_tt.clear()
	var packed := (move & 0xFFF) | ((depth & 0xFF) << 12) | ((flag & 0x3) << 20) | (((score + (1 << 31)) & 0xFFFFFFFF) << 22)
	_tt[key] = packed


func _load(engine: ChessEngine) -> void:
	_board = PackedInt32Array()
	_board.resize(64)
	_king_sq = {WHITE: -1, BLACK: -1}
	for r in range(8):
		for c in range(8):
			var code: int = engine.board[r][c]
			_board[r * 8 + c] = code
			if code == KING:
				_king_sq[WHITE] = r * 8 + c
			elif code == -KING:
				_king_sq[BLACK] = r * 8 + c
	_side = engine.turn
	_castle = engine.castle_rights
	_ep = engine.ep_square.y * 8 + engine.ep_square.x if engine.ep_square.x >= 0 else -1
	_hash = _compute_hash()


func _compute_hash() -> int:
	var h := 0
	for sq in range(64):
		var code := _board[sq]
		if code != EMPTY:
			h ^= _z_piece[_piece_index(code)][sq]
	if _side == BLACK:
		h ^= _z_side
	h ^= _z_castle[_castle]
	if _ep >= 0:
		h ^= _z_ep[_ep & 7]
	return h

func _piece_index(code: int) -> int:
	if code > 0:
		return code - 1
	return 6 + (-code - 1)


func _precompute() -> void:
	_rows = PackedInt32Array()
	_cols = PackedInt32Array()
	_knight_targets = []
	_king_targets = []
	var knight_deltas: Array[Vector2i] = [
		Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
		Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2),
	]
	var king_deltas: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	]
	for sq in range(64):
		var r := sq >> 3
		var c := sq & 7
		_rows.append(r)
		_cols.append(c)
		var kn := PackedInt32Array()
		for d in knight_deltas:
			var nr := r + d.x
			var nc := c + d.y
			if nr >= 0 and nr < 8 and nc >= 0 and nc < 8:
				kn.append(nr * 8 + nc)
		_knight_targets.append(kn)
		var kg := PackedInt32Array()
		for d in king_deltas:
			var nr := r + d.x
			var nc := c + d.y
			if nr >= 0 and nr < 8 and nc >= 0 and nc < 8:
				kg.append(nr * 8 + nc)
		_king_targets.append(kg)


func _init_zobrist() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x9E3779B9
	_z_piece = []
	for p in range(12):
		var row := PackedInt64Array()
		for sq in range(64):
			row.append(rng.randi())
		_z_piece.append(row)
	_z_side = rng.randi()
	_z_castle = []
	for i in range(16):
		_z_castle.append(rng.randi())
	_z_ep = []
	for i in range(8):
		_z_ep.append(rng.randi())
