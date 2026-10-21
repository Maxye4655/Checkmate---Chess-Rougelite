class_name Progress
extends RefCounted
## Challenge stats and unlocks that persist between runs (saved to user://progress.cfg).
##
## Stats are plain counters keyed by name ("wins", "queens_taken", ...). Each entry in
## CHALLENGES watches one stat and unlocks one shop item when its goal is reached.
##
## To add a challenge: add an entry below, record its stat where it happens with
## Progress.add() / Progress.set_max(), and add the item it unlocks to ShopItems.

const SAVE_PATH := "user://progress.cfg"

const CHALLENGES := [
	{"id": "win_3", "text": "Defeat the AI 3 times", "stat": "wins", "goal": 3, "item": "peasants_revolt"},
	{"id": "win_10", "text": "Defeat the AI 10 times", "stat": "wins", "goal": 10, "item": "hypnosis"},
	{"id": "lose_5", "text": "Lose 5 rounds", "stat": "losses", "goal": 5, "item": "phoenix_feather"},
	{"id": "earn_100", "text": "Earn 100 coins in total", "stat": "coins_earned", "goal": 100, "item": "golden_goose"},
	{"id": "queens_20", "text": "Take 20 queens from the AI", "stat": "queens_taken", "goal": 20, "item": "queenbane"},
	{"id": "captures_75", "text": "Capture 75 enemy pieces", "stat": "captures", "goal": 75, "item": "battle_hardened"},
	{"id": "checks_30", "text": "Give check 30 times", "stat": "checks", "goal": 30, "item": "lightning_rod"},
	{"id": "buy_12", "text": "Buy 12 items from the shop", "stat": "items_bought", "goal": 12, "item": "haggler"},
	{"id": "no_undo_win", "text": "Win a round without using an undo", "stat": "wins_no_undo", "goal": 1, "item": "chrono_core"},
	{"id": "fast_win", "text": "Win a round in 30 moves or fewer", "stat": "fast_wins", "goal": 1, "item": "oracle_eye"},
	{"id": "round_5", "text": "Reach round 5 in a single run", "stat": "best_round", "goal": 5, "item": "warlords_banner"},
	{"id": "pawn_queen", "text": "Capture a Queen with a pawn", "stat": "pawn_queen_caps", "goal": 1, "item": "scorched_earth"},
]

static var _stats := {}
static var _done := {}
static var _fresh: Array = []   # item ids unlocked but not yet announced in the shop
static var _loaded := false


# --- Persistence 

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if cfg.has_section("stats"):
		for key in cfg.get_section_keys("stats"):
			_stats[key] = int(cfg.get_value("stats", key, 0))
	if cfg.has_section("done"):
		for key in cfg.get_section_keys("done"):
			_done[key] = true
	_fresh = Array(cfg.get_value("meta", "fresh", []))


static func _save() -> void:
	var cfg := ConfigFile.new()
	for key in _stats:
		cfg.set_value("stats", key, _stats[key])
	for key in _done:
		cfg.set_value("done", key, true)
	cfg.set_value("meta", "fresh", _fresh)
	cfg.save(SAVE_PATH)


# --- Recording stats

static func get_stat(stat: String) -> int:
	_ensure_loaded()
	return int(_stats.get(stat, 0))


static func add(stat: String, amount: int = 1) -> void:
	_ensure_loaded()
	_stats[stat] = get_stat(stat) + amount
	_save()


## For "best ever" stats such as the furthest round reached.
static func set_max(stat: String, value: int) -> void:
	if value > get_stat(stat):
		_stats[stat] = value
		_save()


# --- Challenges 

static func is_done(challenge_id: String) -> bool:
	_ensure_loaded()
	return _done.has(challenge_id)


static func progress_of(ch: Dictionary) -> int:
	return mini(get_stat(str(ch["stat"])), int(ch["goal"]))


static func ratio(ch: Dictionary) -> float:
	return float(progress_of(ch)) / float(ch["goal"])


static func done_count() -> int:
	_ensure_loaded()
	return _done.size()


static func total_count() -> int:
	return CHALLENGES.size()


## Marks every challenge whose goal has been reached and returns the newly
## completed ones. Call after recording stats.
static func check_unlocks() -> Array:
	_ensure_loaded()
	var newly: Array = []
	for ch in CHALLENGES:
		var id := str(ch["id"])
		if _done.has(id):
			continue
		if get_stat(str(ch["stat"])) >= int(ch["goal"]):
			_done[id] = true
			_fresh.append(str(ch["item"]))
			newly.append(ch)
	if not newly.is_empty():
		_save()
	return newly


static func challenge_for_item(item_id: String) -> Dictionary:
	for ch in CHALLENGES:
		if ch["item"] == item_id:
			return ch
	return {}


## Items with no challenge attached are always available.
static func item_unlocked(item_id: String) -> bool:
	var ch := challenge_for_item(item_id)
	return ch.is_empty() or is_done(str(ch["id"]))


## Item ids unlocked since the shop last announced them (clears the list).
static func pop_fresh() -> Array:
	_ensure_loaded()
	var out := _fresh.duplicate()
	if not _fresh.is_empty():
		_fresh.clear()
		_save()
	return out


# --- Debug helpers

static func unlock_all() -> void:
	_ensure_loaded()
	for ch in CHALLENGES:
		_done[str(ch["id"])] = true
	_fresh.clear()
	_save()


static func reset() -> void:
	_ensure_loaded()
	_stats.clear()
	_done.clear()
	_fresh.clear()
	_save()
