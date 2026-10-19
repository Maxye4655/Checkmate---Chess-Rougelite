class_name RunState
extends RefCounted
## Everything that persists between rounds of one "run": coins, owned upgrades,
## how many queens the opponent has earned, and per-round resources.

const BASE_UNDOS := 1
const BASE_REWARD := 2
const WIN_BONUS := 10
const BASE_REROLL_COST := 2
const MAX_INTEREST := 5
const MAX_MOVE_REWARD := 8

# Piece type indices (match the texture file order in the board script).
const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6
const PIECE_VALUE := [0, 1, 3, 3, 5, 9, 0]

var coins := 0
var round_number := 1
var wins := 0
var enemy_queens := 0
var extra_lives := 0
var undos_left := 0
var reroll_cost := BASE_REROLL_COST
var owned := {}   # item id -> times bought


# --- Shop ---------------------------------------------------------------------

func count(id: String) -> int:
	return int(owned.get(id, 0))


func can_buy(id: String) -> bool:
	var item := ShopItems.get_item(id)
	if item["kind"] == "extra_life":
		return extra_lives < int(item["max"])
	return count(id) < int(item["max"])


func buy(id: String) -> bool:
	var item := ShopItems.get_item(id)
	var price := int(item["price"])
	if coins < price or not can_buy(id):
		return false
	coins -= price
	owned[id] = count(id) + 1
	if item["kind"] == "extra_life":
		extra_lives += 1
	return true


func begin_shop() -> void:
	reroll_cost = BASE_REROLL_COST


func try_reroll() -> bool:
	if coins < reroll_cost:
		return false
	coins -= reroll_cost
	reroll_cost += 1
	return true


func use_extra_life() -> bool:
	if extra_lives <= 0:
		return false
	extra_lives -= 1
	return true


func undos_per_round() -> int:
	return BASE_UNDOS + _sum_kind("undos")


func _sum_kind(kind: String) -> int:
	var total := 0
	for id in owned:
		var item := ShopItems.get_item(id)
		if item["kind"] == kind:
			total += int(item.get("amount", 1)) * int(owned[id])
	return total


# --- Rounds -------------------------------------------------------------------

func advance_round(won: bool) -> void:
	if won:
		wins += 1
		enemy_queens += 1
	round_number += 1


## Call right after engine.reset(): refills undos and applies every upgrade
## (and the opponent's extra queens) to the fresh board.
func begin_round(engine: ChessEngine, player_color: int) -> void:
	undos_left = undos_per_round()
	_apply_loadout(engine, player_color)


func _apply_loadout(engine: ChessEngine, player_color: int) -> void:
	var board = engine.board

	var is_my_pawn := func(code: int) -> bool:
		return absi(code) == PAWN and ChessEngine.color_of(code) == player_color
	var is_enemy_pawn := func(code: int) -> bool:
		return absi(code) == PAWN and ChessEngine.color_of(code) != player_color
	# Any enemy piece except the king and existing queens (this engine has no castling).
	var is_enemy_replaceable := func(code: int) -> bool:
		var t := absi(code)
		return ChessEngine.color_of(code) != player_color and t != QUEEN and t != KING

	# 1) Player promotions (best pieces first)
	var promotions: Array[int] = []
	for id in owned:
		var item := ShopItems.get_item(id)
		if item["kind"] == "start_piece":
			for i in range(count(id)):
				promotions.append(int(item["piece"]))
	promotions.sort()
	promotions.reverse()

	var my_pawns := _find_squares(board, is_my_pawn)
	my_pawns.shuffle()
	for piece in promotions:
		if my_pawns.is_empty():
			break
		_replace(board, my_pawns.pop_back(), piece)

	# 2) Enemy pawn removal
	var removals := _sum_kind("remove_enemy_pawn")
	if removals > 0:
		var enemy_pawns := _find_squares(board, is_enemy_pawn)
		enemy_pawns.shuffle()
		for i in range(mini(removals, enemy_pawns.size())):
			var sq: Vector2i = enemy_pawns[i]
			board[sq.y][sq.x] = ChessEngine.Type.EMPTY

	# 3) Opponent queens earned by your wins
	if enemy_queens > 0:
		var candidates := _find_squares(board, is_enemy_replaceable)
		candidates.shuffle()
		for i in range(mini(enemy_queens, candidates.size())):
			_replace(board, candidates[i], QUEEN)


func _find_squares(board, predicate: Callable) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for r in range(8):
		for c in range(8):
			var code: int = board[r][c]
			if code != ChessEngine.Type.EMPTY and predicate.call(code):
				found.append(Vector2i(c, r))
	return found


func _replace(board, square: Vector2i, piece: int) -> void:
	var code: int = board[square.y][square.x]
	board[square.y][square.x] = signi(code) * piece


static func material(board, player_color: int, mine: bool) -> int:
	var total := 0
	for row in board:
		for code in row:
			if code == ChessEngine.Type.EMPTY:
				continue
			if (ChessEngine.color_of(code) == player_color) != mine:
				continue
			total += int(PIECE_VALUE[absi(code)])
	return total


# --- Rewards ------------------------------------------------------------------

## Pays out for the round that just ended. Returns {"lines": [[label, amount]...], "total": int}.
func settle_round(engine: ChessEngine, player_color: int, enemy_start_material: int, won: bool) -> Dictionary:
	var lines: Array = []
	_add_line(lines, "Showing up", BASE_REWARD)
	if won:
		_add_line(lines, "Checkmate bonus", WIN_BONUS)

	var full_moves := int(ceil(engine.history.size() / 2.0))
	_add_line(lines, "Moves played (%d)" % full_moves, mini(int(full_moves * 0.25), MAX_MOVE_REWARD))

	var enemy_now := material(engine.board, player_color, false)
	var captured := maxi(enemy_start_material - enemy_now, 0)
	_add_line(lines, "Material captured (%d)" % captured, int(captured * 0.5))

	if won:
		_add_line(lines, "Round %d bonus" % round_number, round_number)
	_add_line(lines, "Lucky Coin", _sum_kind("bonus_coins"))
	if count("piggy_bank") > 0:
		_add_line(lines, "Interest", mini(int(coins * 0.2), MAX_INTEREST))

	var total := 0
	for line in lines:
		total += int(line[1])
	coins += total
	return {"lines": lines, "total": total}


func _add_line(lines: Array, label: String, amount: int) -> void:
	if amount > 0:
		lines.append([label, amount])
