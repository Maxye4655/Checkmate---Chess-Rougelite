class_name ShopItems
extends RefCounted
## kinds:
##   start_piece        -> promotes one of your pawns at the start of every round ("piece" = type 2..5)
##   undos              -> +"amount" undos every round
##   extra_life         -> single-use: rewinds the board instead of losing
##   interest           -> $1 per $5 held after each round (capped)
##   bonus_coins        -> +"amount" coins after every round
##   remove_enemy_pawn  -> one enemy pawn is removed at the start of every round

const ICON_DIR := "res://Assets/Shop/"

const ITEMS := {
	"knights_oath": {
		"name": "Knight's Oath",
		"desc": "Start every round with one of your pawns promoted to a Knight.",
		"price": 5, "kind": "start_piece", "piece": 2, "max": 2,
	},
	"bishops_blessing": {
		"name": "Bishop's Blessing",
		"desc": "Start every round with one of your pawns promoted to a Bishop.",
		"price": 6, "kind": "start_piece", "piece": 3, "max": 2,
	},
	"rooks_vow": {
		"name": "Rook's Vow",
		"desc": "Start every round with one of your pawns promoted to a Rook.",
		"price": 9, "kind": "start_piece", "piece": 4, "max": 2,
	},
	"queens_gambit": {
		"name": "Queen's Gambit",
		"desc": "Start every round with one of your pawns promoted to a Queen.",
		"price": 16, "kind": "start_piece", "piece": 5, "max": 1,
	},
	"time_turner": {
		"name": "Time Turner",
		"desc": "+2 undos every round.",
		"price": 4, "kind": "undos", "amount": 2, "max": 3,
	},
	"second_wind": {
		"name": "Second Wind",
		"desc": "When you would be checkmated, the board rewinds and you play on. Single use.",
		"price": 8, "kind": "extra_life", "max": 3,
	},
	"piggy_bank": {
		"name": "Piggy Bank",
		"desc": "After each round, earn $1 interest for every $5 you hold (max $5).",
		"price": 7, "kind": "interest", "max": 1,
	},
	"lucky_coin": {
		"name": "Lucky Coin",
		"desc": "+$3 after every round.",
		"price": 5, "kind": "bonus_coins", "amount": 3, "max": 2,
	},
	"pawn_purge": {
		"name": "Pawn Purge",
		"desc": "Start every round with one enemy pawn removed.",
		"price": 8, "kind": "remove_enemy_pawn", "max": 2,
	},
	"danger_sense": {
		"name": "Danger Sense",
		"desc": "Your pieces under attack get a red corner marker.",
		"price": 4, "kind": "danger_sense", "amount": 1, "max": 2,
	},
	"butterfingers": {
		"name": "Butterfingers",
		"desc": "10% of the Ai's moves become random.",
		"price": 8, "kind": "blunder", "amount": 1, "max": 3,
	},
	"bount_hunter": {
		"name": "Bounty Hunter",
		"desc": "+$1 for every captured piece.",
		"price": 10, "kind": "capture_bounty", "amount": 1, "max": 2,
	},
	"consolation_prize": {
		"name": "Consolation Prize",
		"desc": "+$4 every time you lose a round.",
		"price": 6, "kind": "loss_bonus", "amount": 4, "max": 1,
	},
	"unnassuming_book": {
		"name": "Unassuming Book",
		"desc": "Does Nothing?",
		"price": 5, "kind": "unlock", "amount": 1, "max": 5,
	},
	
	# Power-Ups unlocked through Achievements
	
	"peasants_revolt": {
		"name": "Peasants Revolt",
		"desc": "Each round, 3 of your pawns start as knights.",
		"price": 12, "kind": "start_piece", "pieces": [2, 2, 2], "max": 1,
	},
	"hypnosis": {
		"name": "Hypnosis",
		"desc": "30% of the Ai's moves become random",
		"price": 25, "kind": "blunder", "amount": 30, "max": 1,
	},
	"phoenix_feather": {
		"name": "Phoenix Feather",
		"desc": "Every round, the first checkmata against you is undone.",
		"price": 30, "kind": "round_life", "max": 1,
	},
	"golden_goose": {
		"name": "Golden Goose",
		"desc": "+$6 after every round.",
		"price": 19, "kind": "bonus_coins", "amount": 6, "max": 1,
	},
	"queenbane": {
		"name": "Queenbane",
		"desc": "Each round, 1 enemy queen is downgraded to a Bishop.",
		"price": 25, "kind": "downgrade_queen", "amount": 1, "max": 2,
	},
	"battle_hardened": {
		"name": "Battle Hardened",
		"desc": "Once per round, a piece that captures is upgraded to a stronger piece.",
		"price": 20, "kind": "upgrade_on_capture", "amount": 1, "max": 2,
	},
	"lightning_rod": {
		"name": "Lightning Rod",
		"desc": "+$2 each time you give check (maximum of $10 per round).",
		"price": 18, "kind": "check_bounty", "amount": 2, "max": 2,
	},
	"haggler": {
		"name": "Haggler's Handbook",
		"desc": "Everything in the shop costs 25% less.",\
		"price": 10, "kind": "discount", "amount": 25, "max": 1,
	},
	"chrono_core": {
		"name": "Chrono Core",
		"desc": "+5 undos per round.",
		"price": 30, "kind": "undos", "amount": 5, "max": 1,
	},
	"oracle_eye": {
		"name": "Oracle's Eye",
		"desc": "Press H once per round to reveal the best move.",
		"price": 20, "kind": "hint", "amount": 1, "max": 2,
	},
	"warlords_banner": {
		"name": "Warlord's Banner",
		"desc": "Each round, 2 pawns start as rooks and 1 as a bishop.",
		"price": 22, "kind": "start_piece", "pieces": [4, 4, 3], "max": 1,
	},
	"scorched_earth": {
		"name": "Scorched Earth",
		"desc": "Each Round, 3 enemy pawns are incinerated, annihilated, and ereased before the game starts.",
		"price": 16, "kind": "remove_enemy_pawn", "amount": 3, "max": 1,
	},
	
	#Super Secret Power-Up unlocked after the Unnassuming book is purchased 5 times:
	"revolution": {
		"name": "Revolution",
		"desc": "Just as a crop in the field cannot grow without rain, the revolution of the working class cannot grow without Joseph Stalemate.",
		"price": 0, "kind": "revolution", "amount": 1, "max": 1,
	},
}


static func ids() -> Array:
	return ITEMS.keys()


static func get_item(id: String) -> Dictionary:
	return ITEMS[id]

static func is_unlocked(id: String) -> bool:
	return Progress.item_unlocked(id)

static func icon_path(id: String) -> String:
	return "%s%s.png" % [ICON_DIR, id]
