class_name ShopItems
extends RefCounted
## Catalog of everything the player can buy between rounds.
##
## To add an item: add an entry below, give it a pixel-art icon named
## "<id>.png" in res://Assets/Shop/, and (if it needs a brand-new "kind")
## handle that kind in RunState.
##
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
}


static func ids() -> Array:
	return ITEMS.keys()


static func get_item(id: String) -> Dictionary:
	return ITEMS[id]


static func icon_path(id: String) -> String:
	return "%s%s.png" % [ICON_DIR, id]
