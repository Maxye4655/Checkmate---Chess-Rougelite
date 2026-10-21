class_name RunState
extends RefCounted
## Everything that lasts for one "run" (a streak of rounds): coins, owned upgrades,
## the opponent's extra queens, and the per-round resources those upgrades grant.
## Stats that persist between runs live in Progress.

const BASE_UNDOS := 1
const BASE_REWARD := 2
const WIN_BONUS := 10
const BASE_REROLL_COST := 2
const MAX_INTEREST := 5
const MAX_MOVE_REWARD := 8
const MAX_CHECK_BONUS := 10
const MAX_DISCOUNT := 75
const MAX_BLUNDER_CHANCE := 0.75

# Piece type indices (match the texture file order in the board script).
const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6
const PIECE_VALUE := [0, 1, 3, 3, 5, 9, 0]

## What a capturing piece becomes with "upgrade_on_capture".
const UPGRADE_TO := {PAWN: KNIGHT, KNIGHT: ROOK, BISHOP: ROOK, ROOK: QUEEN}

var coins := 0
var round_number := 1
var wins := 0
var enemy_queens := 0
var extra_lives := 0       # bought Second Winds; carry over until used
var round_lives := 0       # Phoenix Feather; refilled every round
var undos_left := 0
var undos_used := 0
var hints_left := 0
var upgrades_left := 0
var round_captures := 0
var round_checks := 0
var reroll_cost := BASE_REROLL_COST
var owned := {}            # item id -> times bought
var revolution_used := false

# --- Shop 

func count(id: String) -> int:
	return int(owned.get(id, 0))


func owns(id: String) -> bool:
	return count(id) > 0


func can_buy(id: String) -> bool:
	
	if id == "revolution" and count("unnassuming_book") < 5:
		return false
	
	if not ShopItems.is_unlocked(id):
		return false
	
	if id == "revolution" and not revolution_unlocked():
		return false
	
	if not ShopItems.is_unlocked(id):
		return false
	var item := ShopItems.get_item(id)
	if item["kind"] == "extra_life":
		return extra_lives < int(item["max"])
	return count(id) < int(item["max"])


## Base price minus any discount (never below $1).
func price_of(id: String) -> int:
	var price := int(ShopItems.get_item(id)["price"])
	var percent_off := mini(_sum_kind("discount"), MAX_DISCOUNT)
	if percent_off <= 0:
		return price
	return maxi(1, roundi(price * (100 - percent_off) / 100.0))


func buy(id: String) -> bool:
	var item := ShopItems.get_item(id)
	var price := price_of(id)
	if coins < price or not can_buy(id):
		return false
	coins -= price
	owned[id] = count(id) + 1
	if item["kind"] == "extra_life":
		extra_lives += 1
	Progress.add("items_bought")
	return true


func begin_shop() -> void:
	reroll_cost = BASE_REROLL_COST


func try_reroll() -> bool:
	if coins < reroll_cost:
		return false
	coins -= reroll_cost
	reroll_cost += 1
	return true

func revolution_unlocked() -> bool:
	return count("unnassuming_book") >= 5

func can_use_revolution() -> bool:
	return owns("revolution") and not revolution_used
	
func use_revolution(
	engine: ChessEngine,
	player_color: int,
	sacrifice_square: Vector2i,
	target_square: Vector2i
) -> bool:
	if not can_use_revolution():
		return false
	
	if not revolution_unlocked():
		return false
	
	var board = engine.board
	if not _valid_square(sacrifice_square) or not _valid_square(target_square):
		return false
	
	var sacrifice: int = board[sacrifice_square.y][sacrifice_square.x]
	var target: int = board[target_square.y][target_square.x]
	
	if sacrifice == ChessEngine.Type.EMPTY:
		return false
	if ChessEngine.color_of(target) == player_color:
		return false
	if absi(target) == KING:
		return false
	
	if PIECE_VALUE[absi(sacrifice)] > PIECE_VALUE[absi(target)]:
		return false
		
	board[sacrifice_square.y][sacrifice_square.x] = ChessEngine.Type.EMPTY
	board[target_square.y][target_square.x] = ChessEngine.Type.EMPTY
	revolution_used = true
	return true
	
func _valid_square(square: Vector2i) -> bool:
	return square.x >= 0 and square.x < 8 and square.y >= 0 and square.y < 8

# --- Per-round resources 

func lives_available() -> int:
	return extra_lives + round_lives


## Spends a free rewind and returns its name, or "" if none are left.
## The refilling Phoenix Feather is spent first so Second Winds are saved.
func use_extra_life() -> String:
	if round_lives > 0:
		round_lives -= 1
		return "Phoenix Feather"
	if extra_lives > 0:
		extra_lives -= 1
		return "Second Wind"
	return ""


func undos_per_round() -> int:
	return BASE_UNDOS + _sum_kind("undos")


func hints_per_round() -> int:
	return _sum_kind("hint")


func ai_blunder_chance() -> float:
	return minf(_sum_kind("blunder") / 100.0, MAX_BLUNDER_CHANCE)


## Battle Hardened: returns the piece type a capturing piece becomes, or 0.
func take_upgrade(piece_type: int) -> int:
	if upgrades_left <= 0 or not UPGRADE_TO.has(piece_type):
		return 0
	upgrades_left -= 1
	return int(UPGRADE_TO[piece_type])


func record_capture() -> void:
	round_captures += 1


func record_check() -> void:
	round_checks += 1


func _sum_kind(kind: String) -> int:
	var total := 0
	for entry in _owned_of_kind(kind):
		total += int(entry["item"].get("amount", 1)) * int(entry["count"])
	return total


## [{"id", "item", "count"}] for every owned item of this kind.
func _owned_of_kind(kind: String) -> Array:
	var found: Array = []
	for id in owned:
		var item := ShopItems.get_item(id)
		if item["kind"] == kind and int(owned[id]) > 0:
			found.append({"id": id, "item": item, "count": int(owned[id])})
	return found


# --- Rounds

func advance_round(won: bool) -> void:
	if won:
		wins += 1
		enemy_queens += 1
	round_number += 1


## Call right after engine.reset(): refills per-round resources and applies every
## upgrade (and the opponent's extra queens) to the fresh board.
func begin_round(engine: ChessEngine, player_color: int) -> void:
	undos_left = undos_per_round()
	undos_used = 0
	hints_left = hints_per_round()
	upgrades_left = _sum_kind("upgrade_on_capture")
	round_lives = _sum_kind("round_life")
	round_captures = 0
	round_checks = 0
	revolution_used = false
	_apply_loadout(engine, player_color)


func _apply_loadout(engine: ChessEngine, player_color: int) -> void:
	var board = engine.board

	var is_my_pawn := func(code: int) -> bool:
		return absi(code) == PAWN and ChessEngine.color_of(code) == player_color
	var is_enemy_pawn := func(code: int) -> bool:
		return absi(code) == PAWN and ChessEngine.color_of(code) != player_color
	var is_enemy_queen := func(code: int) -> bool:
		return absi(code) == QUEEN and ChessEngine.color_of(code) != player_color
	# Any enemy piece except the king and existing queens (the engine has no castling).
	var is_enemy_replaceable := func(code: int) -> bool:
		var t := absi(code)
		return ChessEngine.color_of(code) != player_color and t != QUEEN and t != KING

	# 1) Player promotions (best pieces first)
	var promotions: Array[int] = []
	for entry in _owned_of_kind("start_piece"):
		for i in range(int(entry["count"])):
			for piece in entry["item"]["pieces"]:
				promotions.append(int(piece))
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

	# 4) Queenbane: knock enemy queens down to bishops (after step 3 so it can undo them)
	var downgrades := _sum_kind("downgrade_queen")
	if downgrades > 0:
		var queens := _find_squares(board, is_enemy_queen)
		queens.shuffle()
		for i in range(mini(downgrades, queens.size())):
			_replace(board, queens[i], BISHOP)


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


# --- Rewards 

## Pays out for the round that just ended. Returns {"lines": [[label, amount]...], "total": int}.
func settle_round(engine: ChessEngine, player_color: int, enemy_start_material: int, won: bool, lost: bool = false) -> Dictionary:
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

	for entry in _owned_of_kind("bonus_coins"):
		_add_line(lines, str(entry["item"]["name"]), int(entry["item"]["amount"]) * int(entry["count"]))
	for entry in _owned_of_kind("capture_bounty"):
		var per_capture := int(entry["item"]["amount"]) * int(entry["count"])
		_add_line(lines, "%s (%d)" % [entry["item"]["name"], round_captures], per_capture * round_captures)
	var per_check := _sum_kind("check_bounty")
	if per_check > 0:
		_add_line(lines, "Lightning Rod (%d)" % round_checks, mini(per_check * round_checks, MAX_CHECK_BONUS))
	if lost:
		for entry in _owned_of_kind("loss_bonus"):
			_add_line(lines, str(entry["item"]["name"]), int(entry["item"]["amount"]) * int(entry["count"]))
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
