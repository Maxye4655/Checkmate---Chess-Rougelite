class_name ShopScreen
extends CanvasLayer
## Balatro-flavoured between-rounds shop: calm scrolling backdrop, dealt cards,
## coin counter, reroll, and a big "Next Round" button.
##
## Readability rules used throughout: nothing smaller than 16px, body text is
## near-white on dark panels, headings get an outline, and the layout is sized
## to fit the 1152x648 base resolution without scrolling.
##
## Usage:  var shop := ShopScreen.new()
##         shop.setup(run_state, last_reward)
##         shop.next_round_requested.connect(...)
##         add_child(shop)

signal next_round_requested

const FONT_PATH := "res://Assets/CheckMate.ttf"
const COIN_ICON_PATH := "res://Assets/UI/coin.png"   # 16x16 pixel art, drawn at 1x or 2x
const CARD_SIZE := Vector2(224, 330)
const REWARD_WIDTH := 340.0
const OFFER_COUNT := 3

const PANEL := Color("2a343a")
const PANEL_DARK := Color("1b252a")
const ACCENT := Color("648a9d")
const ACCENT_LIGHT := Color("9cc3d6")
const TEXT := Color("ffffff")
const TEXT_SOFT := Color("dde6ea")     # body copy
const TEXT_DIM := Color("aab8be")      # secondary labels (still high contrast)
const OUTLINE := Color("0b1115")
const GOLD := Color("ffd35c")
const GOOD := Color("8fe0a0")
const BAD := Color("ff8077")
const BUY_COLOR := Color("2f6fb0")
const REROLL_COLOR := Color("b5532f")
const NEXT_COLOR := Color("3f8a5a")

var run: RunState
var reward: Dictionary = {}

var _font: Font
var _coin_texture: Texture2D
var _root: Control
var _coin_label: Label
var _cards_row: HBoxContainer
var _reroll_button: Button
var _owned_row: HBoxContainer
var _card_buttons := {}      # item id -> Button
var _displayed_coins := 0
var _closing := false


## Slow, low-contrast diamond lattice so text never fights the background.
class Backdrop extends Control:
	const STEP := 72.0
	const BASE := Color("111b21")
	const LIGHT := Color("15232b")
	var _t := 0.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		_t += delta * 12.0
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BASE)
		var off := fmod(_t, STEP * 2.0)
		var cols := int(size.x / STEP) + 4
		var rows := int(size.y / STEP) + 4
		var h := STEP * 0.5
		for iy in range(-2, rows):
			for ix in range(-2, cols):
				if posmod(ix + iy, 2) != 0:
					continue
				var c := Vector2(ix * STEP + off, iy * STEP + off)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)
				]), LIGHT)


func setup(run_state: RunState, last_reward: Dictionary) -> void:
	run = run_state
	reward = last_reward
	run.begin_shop()


func _ready() -> void:
	layer = 50
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	if ResourceLoader.exists(COIN_ICON_PATH):
		_coin_texture = load(COIN_ICON_PATH)
	_displayed_coins = maxi(run.coins - int(reward.get("total", 0)), 0)

	add_child(Backdrop.new())

	_root = MarginContainer.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		_root.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		_root.add_theme_constant_override("margin_" + side, 20)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_root.add_child(column)

	column.add_child(_build_header())

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 24)
	column.add_child(middle)
	middle.add_child(_build_reward_panel())
	middle.add_child(_build_offer_area())

	column.add_child(_build_footer())

	_roll_offers()
	_refresh_owned()
	_refresh_affordability()

	_root.modulate.a = 0.0
	_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.3)
	_animate_initial_coin_count()


# =============================================================================
# Layout
# =============================================================================

func _build_header() -> Control:
	var row := HBoxContainer.new()

	var sign_panel := PanelContainer.new()
	sign_panel.add_theme_stylebox_override("panel", _box(PANEL_DARK, GOLD, 10, 4, 12))
	sign_panel.add_child(_label("SHOP", 40, GOLD, 6))
	row.add_child(sign_panel)
	_sway(sign_panel)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var coin_panel := PanelContainer.new()
	coin_panel.add_theme_stylebox_override("panel", _box(PANEL_DARK, GOLD, 10, 3, 10))
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 12)
	coin_panel.add_child(coin_row)
	coin_row.add_child(_make_coin_icon(32))
	_coin_label = _label(str(_displayed_coins), 38, GOLD, 5)
	_coin_label.custom_minimum_size.x = 100
	_coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_row.add_child(_coin_label)
	row.add_child(coin_panel)
	return row


func _build_reward_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(REWARD_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _box(PANEL_DARK, ACCENT, 10, 3, 18))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_label("LAST ROUND", 26, ACCENT_LIGHT, 4))

	var lines: Array = reward.get("lines", [])
	if lines.is_empty():
		box.add_child(_label("Nothing earned", 20, TEXT_DIM))
	for i in range(lines.size()):
		var row := HBoxContainer.new()
		var name_label := _label(str(lines[i][0]), 20, TEXT_SOFT)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(name_label)
		row.add_child(_label("+$%d" % int(lines[i][1]), 22, GOOD))
		box.add_child(row)
		_fade_in(row, 0.25 + i * 0.12)

	box.add_child(HSeparator.new())
	var total_row := HBoxContainer.new()
	var total_name := _label("TOTAL", 24, TEXT)
	total_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	total_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_row.add_child(total_name)
	total_row.add_child(_label("+$%d" % int(reward.get("total", 0)), 30, GOLD, 4))
	box.add_child(total_row)
	_fade_in(total_row, 0.35 + lines.size() * 0.12)
	return panel


func _build_offer_area() -> Control:
	var area := VBoxContainer.new()
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_theme_constant_override("separation", 12)

	# Heading and reroll share one row to keep the cards as tall as possible.
	var head := HBoxContainer.new()
	var title := _label("BUY A BOOST", 26, TEXT, 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_reroll_button = _button("Reroll", REROLL_COLOR, Vector2(190, 46), 22)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	head.add_child(_reroll_button)
	area.add_child(head)

	_cards_row = HBoxContainer.new()
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_row.add_theme_constant_override("separation", 18)
	area.add_child(_cards_row)
	return area


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var owned_box := VBoxContainer.new()
	owned_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var owned_title := _label("OWNED  (hover an icon for details)", 18, TEXT_DIM)
	owned_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	owned_box.add_child(owned_title)
	_owned_row = HBoxContainer.new()
	_owned_row.custom_minimum_size.y = 36
	_owned_row.add_theme_constant_override("separation", 14)
	owned_box.add_child(_owned_row)
	row.add_child(owned_box)

	var next_button := _button("Next Round", NEXT_COLOR, Vector2(280, 60), 30)
	next_button.pressed.connect(_on_next_pressed)
	row.add_child(next_button)
	return row


# =============================================================================
# Offers
# =============================================================================

func _available_ids() -> Array:
	var pool: Array = []
	for id in ShopItems.ids():
		if run.can_buy(id):
			pool.append(id)
	return pool


func _roll_offers() -> void:
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()
	_card_buttons.clear()

	var pool := _available_ids()
	pool.shuffle()
	var picks := pool.slice(0, mini(OFFER_COUNT, pool.size()))

	if picks.is_empty():
		_cards_row.add_child(_label("Sold out - nothing left to buy!", 26, TEXT_DIM))
		return

	for i in range(picks.size()):
		var card := _build_card(picks[i])
		_cards_row.add_child(card)
		_deal_card(card, i)


func _build_card(id: String) -> PanelContainer:
	var item := ShopItems.get_item(id)
	var price := int(item["price"])

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", _box(PANEL, ACCENT, 12, 3, 14))
	card.resized.connect(func() -> void: card.pivot_offset = card.size / 2.0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	# Name (two lines reserved so every card lines up)
	var title := _label(str(item["name"]), 22, TEXT, 3)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(0, 52)
	box.add_child(title)

	var icon_holder := CenterContainer.new()
	icon_holder.add_child(_make_icon(id, 96))
	box.add_child(icon_holder)

	var desc := _label(str(item["desc"]), 18, TEXT_SOFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	var held := run.extra_lives if item["kind"] == "extra_life" else run.count(id)
	if held > 0:
		var held_label := "Held" if item["kind"] == "extra_life" else "Owned"
		box.add_child(_label("%s %d / %d" % [held_label, held, int(item["max"])], 16, ACCENT_LIGHT))

	var buy := _button("", BUY_COLOR, Vector2(0, 44), 22)
	_set_price(buy, "Buy", price)
	buy.pressed.connect(_on_buy_pressed.bind(card, id, buy))
	box.add_child(buy)
	_card_buttons[id] = buy

	var rest_tilt := randf_range(-0.03, 0.03)
	card.set_meta("rest_tilt", rest_tilt)
	card.mouse_entered.connect(_tilt_card.bind(card, 1.05, 0.0))
	card.mouse_exited.connect(_tilt_card.bind(card, 1.0, rest_tilt))
	return card


func _deal_card(card: Control, index: int) -> void:
	var rest_tilt: float = card.get_meta("rest_tilt", 0.0)
	card.scale = Vector2(0.4, 0.4)
	card.modulate.a = 0.0
	card.rotation = randf_range(-0.5, 0.5)
	var tween := card.create_tween().set_parallel(true)
	var delay := 0.12 * index + 0.1
	tween.tween_property(card, "scale", Vector2.ONE, 0.45).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation", rest_tilt, 0.45).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, 0.2).set_delay(delay)


func _tilt_card(card: Control, target_scale: float, target_rotation: float) -> void:
	if card.get_meta("sold", false):
		return
	var old = card.get_meta("hover_tween", null)
	if old is Tween and old.is_valid():
		old.kill()
	var tween := card.create_tween().set_parallel(true)
	tween.tween_property(card, "scale", Vector2.ONE * target_scale, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation", target_rotation, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	card.set_meta("hover_tween", tween)


func _on_buy_pressed(card: Control, id: String, button: Button) -> void:
	if run.buy(id):
		_animate_coin_change()
		card.set_meta("sold", true)
		button.icon = null
		button.text = "SOLD"
		button.disabled = true
		card.modulate = Color(0.7, 0.7, 0.7)
		_punch(card, 1.08)
		_refresh_owned()
	else:
		_wiggle(card)
		_punch(_coin_label, 1.3)
	_refresh_affordability()


func _on_reroll_pressed() -> void:
	if not run.try_reroll():
		return
	_animate_coin_change()
	_roll_offers()
	_refresh_affordability()


func _on_next_pressed() -> void:
	if _closing:
		return
	_closing = true
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void: next_round_requested.emit())


func _refresh_affordability() -> void:
	for id in _card_buttons:
		var button: Button = _card_buttons[id]
		if button.disabled:
			continue
		var color := TEXT if run.coins >= int(ShopItems.get_item(id)["price"]) else BAD
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_hover_color", color)
	_set_price(_reroll_button, "Reroll", run.reroll_cost)
	_reroll_button.disabled = run.coins < run.reroll_cost or _available_ids().is_empty()


func _refresh_owned() -> void:
	for child in _owned_row.get_children():
		_owned_row.remove_child(child)
		child.queue_free()
	for id in run.owned:
		var item := ShopItems.get_item(id)
		var amount := run.extra_lives if item["kind"] == "extra_life" else run.count(id)
		if amount <= 0:
			continue
		var slot := HBoxContainer.new()
		slot.add_theme_constant_override("separation", 4)
		var icon := _make_icon(id, 32)
		icon.tooltip_text = "%s - %s" % [item["name"], item["desc"]]
		slot.add_child(icon)
		if amount > 1:
			slot.add_child(_label("x%d" % amount, 20, TEXT_SOFT))
		_owned_row.add_child(slot)


# =============================================================================
# Coins
# =============================================================================

func _set_coin_display(value: float) -> void:
	_displayed_coins = int(value)
	if is_instance_valid(_coin_label):
		_coin_label.text = str(_displayed_coins)


func _animate_initial_coin_count() -> void:
	var total := int(reward.get("total", 0))
	if total <= 0:
		_set_coin_display(run.coins)
		return
	var lines: Array = reward.get("lines", [])
	var tween := create_tween()
	tween.tween_interval(0.4 + lines.size() * 0.12)
	tween.tween_method(_set_coin_display, float(_displayed_coins), float(run.coins), 0.9)


func _animate_coin_change() -> void:
	create_tween().tween_method(_set_coin_display, float(_displayed_coins), float(run.coins), 0.3)
	_punch(_coin_label, 1.25)


## "Buy 6 [coin]" with the pixel coin if you've drawn one, otherwise "Buy $6".
func _set_price(button: Button, prefix: String, amount: int) -> void:
	if _coin_texture:
		button.text = ("%s %d" % [prefix, amount]).strip_edges()
		button.icon = _coin_texture
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.expand_icon = false
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		button.text = ("%s $%d" % [prefix, amount]).strip_edges()


# =============================================================================
# Small animation helpers
# =============================================================================

func _sway(control: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(control):
		return
	control.pivot_offset = Vector2(control.size.x / 2.0, 0.0)
	control.rotation = -0.02
	var tween := control.create_tween().set_loops()
	tween.tween_property(control, "rotation", 0.02, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, "rotation", -0.02, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _punch(control: Control, amount: float) -> void:
	if not is_instance_valid(control):
		return
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2.ONE * amount
	control.create_tween().tween_property(control, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _wiggle(control: Control) -> void:
	var base: float = control.get_meta("rest_tilt", 0.0)
	var tween := control.create_tween()
	for angle in [0.06, -0.06, 0.04, -0.04, 0.0]:
		tween.tween_property(control, "rotation", base + angle, 0.05)


func _fade_in(control: Control, delay: float) -> void:
	control.modulate.a = 0.0
	control.create_tween().tween_property(control, "modulate:a", 1.0, 0.25).set_delay(delay)


# =============================================================================
# Factories
# =============================================================================

func _box(bg: Color, border: Color, radius: int, border_width: int, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box


## outline > 0 adds a dark stroke so headings stay legible over anything.
func _label(text: String, size: int, color: Color, outline: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", OUTLINE)
		label.add_theme_constant_override("outline_size", outline)
	if _font:
		label.add_theme_font_override("font", _font)
	return label


func _button(text: String, color: Color, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _box(color, color.lightened(0.35), 8, 3, 6))
	button.add_theme_stylebox_override("hover", _box(color.lightened(0.18), TEXT, 8, 3, 6))
	button.add_theme_stylebox_override("pressed", _box(color.darkened(0.25), color.lightened(0.35), 8, 3, 6))
	button.add_theme_stylebox_override("disabled", _box(PANEL_DARK, TEXT_DIM, 8, 3, 6))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_disabled_color", TEXT_DIM)
	button.add_theme_color_override("font_outline_color", OUTLINE)
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_font_size_override("font_size", font_size)
	if _font:
		button.add_theme_font_override("font", _font)
	button.button_down.connect(func() -> void: _punch(button, 0.95))
	return button


## Uses res://Assets/Shop/<id>.png when it exists, otherwise a coloured
## placeholder tile with the item's first letter.
func _make_icon(id: String, px: int) -> Control:
	var path := ShopItems.icon_path(id)
	if ResourceLoader.exists(path):
		var rect := TextureRect.new()
		rect.texture = load(path)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.custom_minimum_size = Vector2(px, px)
		return rect

	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(px, px)
	var tint := Color.from_hsv(posmod(id.hash(), 360) / 360.0, 0.45, 0.55)
	tile.add_theme_stylebox_override("panel", _box(tint, TEXT_DIM, 8, 2, 0))
	var letter := _label(str(ShopItems.get_item(id)["name"]).substr(0, 1), int(px * 0.55), TEXT, 3)
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(letter)
	return tile


func _make_coin_icon(px: int) -> Control:
	if _coin_texture:
		var rect := TextureRect.new()
		rect.texture = _coin_texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.custom_minimum_size = Vector2(px, px)
		return rect
	var disc := Panel.new()
	disc.custom_minimum_size = Vector2(px, px)
	disc.add_theme_stylebox_override("panel", _box(GOLD, GOLD.darkened(0.35), px / 2, 3, 0))
	return disc
