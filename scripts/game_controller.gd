extends Node3D

const MARCH_TYPES := [
	{"name": "Camp", "visibility": 1.0},
	{"name": "March Quietly", "visibility": 0.5},
	{"name": "Kick Up Dust", "visibility": 2.0}
]

const TERRAIN_TYPES := ["open", "difficult", "no_escape", "city"]
const TERRAIN_LABELS := {
	"open": "Open Ground",
	"difficult": "Difficult Ground",
	"no_escape": "No Escape",
	"city": "City"
}

@export var troop_divisor_max := 10
@export var starting_troops := 100000
@export var enemy_territory_bonus := 1000

var _players := []
var _situations := []
var _current_player := 0
var _awaiting_accept := false
var _awaiting_resolution := false
var _last_resolution_lines: Array = []
var _pending_resolution := false
var _pending_resolution_for := [false, false]
var _pending_resolution_data := {"old": [0, 0], "new": [0, 0]}
var _last_round_totals := [0, 0]
var _last_round_plans := {"p1": [], "p2": []}

var _plan_rows := {}
var _situation_cards := []
var _plan_cards := []
var _hit_marker: MeshInstance3D = null
var _visible_indices := []

@onready var _cards_root: Node3D = $World/CardsRoot
@onready var _camera: Camera3D = $World/Camera3D
@onready var _turn_label: Label = $UI/HUD/HUDBox/TurnLabel
@onready var _troops_label: Label = $UI/HUD/HUDBox/TroopsLabel
@onready var _loss_label: Label = $UI/HUD/HUDBox/LossLabel
@onready var _remaining_label: Label = $UI/HUD/HUDBox/RemainingLabel
@onready var _enemy_troops_label: Label = $UI/HUD/HUDBox/EnemyTroopsLabel
@onready var _terrain_select: OptionButton = $UI/HUD/HUDBox/SituationControls/TerrainSelect
@onready var _perspective_select: OptionButton = $UI/HUD/HUDBox/SituationControls/PerspectiveSelect
@onready var _add_situation_button: Button = $UI/HUD/HUDBox/SituationControls/AddSituationButton
@onready var _plan_controls_root: Control = $UI/PlanControlsRoot
@onready var _end_turn_button: Button = $UI/HUD/EndTurnButton
@onready var _overlay: Control = $UI/TurnOverlay
@onready var _accept_button: Button = $UI/TurnOverlay/AcceptTurnButton
@onready var _resolution_overlay: Control = $UI/ResolutionOverlay
@onready var _resolution_list: VBoxContainer = $UI/ResolutionOverlay/ResolutionPanel/ResolutionBox/ResolutionList
@onready var _resolution_accept: Button = $UI/ResolutionOverlay/ResolutionPanel/ResolutionBox/ResolutionAcceptButton
@onready var _agent: Node = $AgentTcpServer

var _card_scene := preload("res://scenes/Card3D.tscn")
var _plan_card_scene := preload("res://scenes/PlanCard3D.tscn")

func _ready() -> void:
	add_to_group("game_controller")
	_init_game()
	_build_cards()
	_build_plan_list()
	_update_display()
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_accept_button.pressed.connect(_on_accept_turn_pressed)
	_resolution_accept.pressed.connect(_on_accept_resolution_pressed)
	_add_situation_button.pressed.connect(_on_add_situation_pressed)
	_setup_situation_controls()
	if _agent != null and _agent.has_method("set_game_controller"):
		_agent.set_game_controller(self)
	_update_agent_state()
	set_process(true)
	set_process_input(true)
	_build_hit_marker()

func _build_hit_marker() -> void:
	_hit_marker = MeshInstance3D.new()
	_hit_marker.name = "HitMarker"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	_hit_marker.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.2, 0.2)
	mat.emission = Color(1, 0.2, 0.2)
	mat.emission_energy = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hit_marker.material_override = mat
	_hit_marker.visible = false
	_cards_root.add_child(_hit_marker)

func _setup_situation_controls() -> void:
	_terrain_select.clear()
	for terrain in TERRAIN_TYPES:
		_terrain_select.add_item(TERRAIN_LABELS.get(terrain, terrain))
	_terrain_select.select(0)
	_perspective_select.clear()
	_perspective_select.add_item("Home")
	_perspective_select.add_item("Enemy")
	_perspective_select.add_item("Neutral")
	_perspective_select.select(0)

func _on_add_situation_pressed() -> void:
	var terrain = TERRAIN_TYPES[_terrain_select.selected]
	var perspective_index = _perspective_select.selected
	var perspective = "home"
	if perspective_index == 1:
		perspective = "enemy"
	elif perspective_index == 2:
		perspective = "neutral"
	_add_or_get_situation(_current_player, terrain, perspective)
	_rebuild_situations()

func _process(_delta: float) -> void:
	_update_plan_controls_positions()

func _input(event: InputEvent) -> void:
	if _awaiting_accept or _awaiting_resolution:
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_forward_plan_ui_input(event)

func _forward_plan_ui_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var mouse_pos: Vector2
	if event is InputEventMouseButton:
		mouse_pos = event.position
	elif event is InputEventMouseMotion:
		mouse_pos = event.position
	else:
		return
	var from = _camera.project_ray_origin(mouse_pos)
	var dir = _camera.project_ray_normal(mouse_pos)
	var space = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var hit = space.intersect_ray(params)
	if hit.is_empty():
		return
	var collider = hit.get("collider", null)
	if collider == null:
		return
	var plan_card: Node = collider.get_parent()
	if plan_card == null or not plan_card.has_method("get_ui_viewport"):
		return
	var ui_viewport: SubViewport = plan_card.get_ui_viewport()
	var ui_area: Area3D = plan_card.get_ui_area()
	if ui_area == null or ui_viewport == null:
		return
	if collider != ui_area:
		return
	var ui_quad: Node3D = plan_card.get_node_or_null("UIQuad")
	if ui_quad == null:
		return
	var ui_local = plan_card.ui_quad_local_from_ray(from, dir)
	var ui_pos = plan_card.ui_quad_to_viewport(ui_local)
	var forwarded = event.duplicate()
	if forwarded is InputEventMouseButton:
		forwarded.position = ui_pos
		forwarded.global_position = ui_pos
	elif forwarded is InputEventMouseMotion:
		forwarded.position = ui_pos
		forwarded.global_position = ui_pos
	ui_viewport.push_input(forwarded)
	var marker_pos = ui_quad.to_global(Vector3(ui_local.x, 0.0, ui_local.z))
	_show_hit_marker(marker_pos, ui_quad.global_basis)

func _show_hit_marker(world_pos: Vector3, basis: Basis) -> void:
	if _hit_marker == null:
		return
	_hit_marker.global_position = world_pos
	_hit_marker.global_basis = basis
	_hit_marker.visible = true

func _hide_hit_marker() -> void:
	if _hit_marker != null:
		_hit_marker.visible = false

func _init_game() -> void:
	_players = []
	for i in range(2):
		_players.append({
			"total_troops": starting_troops,
			"last_losses": 0
		})
	_situations = []
	_current_player = 0
	_awaiting_accept = false
	_awaiting_resolution = false
	_last_resolution_lines.clear()
	_last_round_totals = [_players[0]["total_troops"], _players[1]["total_troops"]]
	_last_round_plans = {"p1": [], "p2": []}

func _build_plan_list() -> void:
	_plan_rows.clear()
	for i in range(_plan_cards.size()):
		var plan_card: Node = _plan_cards[i]
		if plan_card.has_method("get_ui_root"):
			var ui_root: Control = plan_card.get_ui_root()
			for child in ui_root.get_children():
				child.queue_free()
	for i in range(_situations.size()):
		var plan_card: Node = _plan_cards[i]
		if not plan_card.has_method("get_ui_root"):
			continue
		var row := HBoxContainer.new()
		row.name = "PlanRow_%d" % i
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.custom_minimum_size = Vector2(560, 96)
		row.z_index = 20
		row.z_as_relative = false
		row.scale = Vector2(2.2, 2.2)
		row.add_theme_constant_override("separation", 8)
		var button_style_normal = _make_button_style(Color(0.7, 0.72, 0.75))
		var button_style_hover = _make_button_style(Color(0.85, 0.88, 0.92))
		var button_style_pressed = _make_button_style(Color(0.6, 0.62, 0.66))
		var minus_button := Button.new()
		minus_button.text = "-"
		minus_button.custom_minimum_size = Vector2(48, 48)
		minus_button.add_theme_font_size_override("font_size", 28)
		minus_button.add_theme_stylebox_override("normal", button_style_normal)
		minus_button.add_theme_stylebox_override("hover", button_style_hover)
		minus_button.add_theme_stylebox_override("pressed", button_style_pressed)
		minus_button.pressed.connect(_on_plan_adjust.bind(i, -1))
		row.add_child(minus_button)
		var divisions_label := Label.new()
		divisions_label.text = "0"
		divisions_label.custom_minimum_size = Vector2(80, 0)
		divisions_label.add_theme_font_size_override("font_size", 26)
		divisions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(divisions_label)
		var plus_button := Button.new()
		plus_button.text = "+"
		plus_button.custom_minimum_size = Vector2(48, 48)
		plus_button.add_theme_font_size_override("font_size", 28)
		plus_button.add_theme_stylebox_override("normal", button_style_normal)
		plus_button.add_theme_stylebox_override("hover", button_style_hover)
		plus_button.add_theme_stylebox_override("pressed", button_style_pressed)
		plus_button.pressed.connect(_on_plan_adjust.bind(i, 1))
		row.add_child(plus_button)
		var march_select := OptionButton.new()
		for m in MARCH_TYPES:
			march_select.add_item(m["name"])
		march_select.custom_minimum_size = Vector2(260, 48)
		march_select.add_theme_font_size_override("font_size", 24)
		march_select.add_theme_stylebox_override("normal", button_style_normal)
		march_select.add_theme_stylebox_override("hover", button_style_hover)
		march_select.add_theme_stylebox_override("pressed", button_style_pressed)
		march_select.item_selected.connect(_on_march_selected.bind(i))
		row.add_child(march_select)
		var ui_root: Control = plan_card.get_ui_root()
		ui_root.add_child(row)
		_plan_rows[i] = {
			"divisions_label": divisions_label,
			"minus": minus_button,
			"plus": plus_button,
			"march": march_select,
			"row": row,
			"plan_card": plan_card
		}
	call_deferred("_update_plan_controls_positions")

func _build_cards() -> void:
	for child in _cards_root.get_children():
		child.queue_free()
	_situation_cards.clear()
	_plan_cards.clear()
	var spacing := 3.0
	var start_x := -((float(_situations.size() - 1)) * spacing) * 0.5
	var surface_y := 0.14
	for i in range(_situations.size()):
		var situation_card = _card_scene.instantiate()
		situation_card.name = "SituationCard_%d" % i
		situation_card.position = Vector3(start_x + i * spacing, surface_y, -1.4)
		_cards_root.add_child(situation_card)
		_situation_cards.append(situation_card)
		var plan_card = _plan_card_scene.instantiate()
		plan_card.name = "PlanCard_%d" % i
		plan_card.position = Vector3(start_x + i * spacing, surface_y, 1.4)
		_cards_root.add_child(plan_card)
		plan_card.set_card_color(Color(0.8, 0.87, 0.95))
		_plan_cards.append(plan_card)

func _compute_visible_indices() -> void:
	_visible_indices.clear()
	for i in range(_situations.size()):
		if _is_visible_to_current(i):
			_visible_indices.append(i)

func _layout_cards() -> void:
	var count := _visible_indices.size()
	if count == 0:
		return
	var spacing := 3.0
	var start_x := -((float(count - 1)) * spacing) * 0.5
	var surface_y := 0.14
	for slot in range(count):
		var idx = _visible_indices[slot]
		var x = start_x + slot * spacing
		_situation_cards[idx].position = Vector3(x, surface_y, -1.4)
		_plan_cards[idx].position = Vector3(x, surface_y, 1.4)
		_situation_cards[idx].visible = true
		_plan_cards[idx].visible = true

func _is_visible_to_current(index: int) -> bool:
	if index < 0 or index >= _situations.size():
		return false
	return bool(_situations[index]["revealed"][_current_player])

func _update_display() -> void:
	_turn_label.text = "Player %d Turn" % (_current_player + 1)
	var total_troops: int = _players[_current_player]["total_troops"]
	_troops_label.text = "Total Troops: %d" % total_troops
	var enemy_idx = 1 - _current_player
	_enemy_troops_label.text = "Enemy Troops: %d" % _players[enemy_idx]["total_troops"]
	_loss_label.text = "Losses Last Turn: %d" % _players[_current_player]["last_losses"]
	_remaining_label.text = "Divisions Remaining: %d" % _remaining_divisions()
	_compute_visible_indices()
	_layout_cards()
	for i in range(_situations.size()):
		var row = _plan_rows.get(i, null)
		if row == null:
			continue
		var plan = _get_plan(_current_player, i)
		row["divisions_label"].text = "%d" % plan["divisions"]
		row["march"].select(plan["march_type"])
		row["minus"].disabled = plan["divisions"] <= 0
		row["plus"].disabled = _remaining_divisions() <= 0
		row["row"].visible = _is_visible_to_current(i) and not _awaiting_accept and not _awaiting_resolution
	for i in range(_situations.size()):
		if _is_visible_to_current(i):
			_update_situation_card(i)
			_update_plan_card(i)
		else:
			_situation_cards[i].visible = false
			_plan_cards[i].visible = false
	_overlay.visible = _awaiting_accept
	_resolution_overlay.visible = _awaiting_resolution
	_update_agent_state()
	_update_resolution_overlay()

func _update_plan_controls_positions() -> void:
	if _plan_controls_root == null or _camera == null:
		return
	for i in range(_situations.size()):
		var row_data = _plan_rows.get(i, null)
		if row_data == null:
			continue
		var row: Control = row_data["row"]
		var size = row.get_combined_minimum_size()
		if size == Vector2.ZERO:
			size = row.custom_minimum_size
		row.set_anchors_preset(Control.PRESET_TOP_LEFT)
		row.size = size
		row.position = Vector2(40, 24)
		row.visible = _is_visible_to_current(i) and not _awaiting_accept and not _awaiting_resolution

func _make_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _update_situation_card(index: int) -> void:
	var situation = _situations[index]
	var enemy_idx = 1 - _current_player
	var perspective := _perspective_label(_current_player, situation)
	var terrain_label: String = str(TERRAIN_LABELS.get(situation["terrain"], situation["terrain"]))
	var apparent := _apparent_enemy_troops(enemy_idx, index)
	var text := "%s\nTerritory: %s\nApparent Troops: %s" % [
		terrain_label,
		perspective,
		apparent
	]
	_situation_cards[index].set_text(text)

func _update_plan_card(index: int) -> void:
	var plan = _get_plan(_current_player, index)
	var troops = _divisions_to_troops(_current_player, plan["divisions"])
	var enemy_text := "Enemy: Unknown"
	var text := "Troops: %d\n%s" % [
		troops,
		enemy_text
	]
	_plan_cards[index].set_text(text)

func _on_plan_adjust(index: int, delta: int) -> void:
	if _awaiting_accept:
		return
	var plan = _get_plan(_current_player, index)
	var new_value: int = int(plan["divisions"]) + delta
	new_value = clamp(new_value, 0, troop_divisor_max)
	if delta > 0 and _remaining_divisions() <= 0:
		return
	plan["divisions"] = new_value
	_set_plan(_current_player, index, plan)
	_update_display()

func _on_march_selected(selection: int, index: int) -> void:
	if _awaiting_accept:
		return
	var plan = _get_plan(_current_player, index)
	plan["march_type"] = selection
	_set_plan(_current_player, index, plan)
	_update_display()

func _remaining_divisions() -> int:
	var used := 0
	for i in range(_situations.size()):
		var plan = _get_plan(_current_player, i)
		used += plan["divisions"]
	return max(0, troop_divisor_max - used)

func _get_plan(player_idx: int, situation_idx: int) -> Dictionary:
	var situation = _situations[situation_idx]
	if player_idx == 0:
		return situation["p1"]
	return situation["p2"]

func _set_plan(player_idx: int, situation_idx: int, plan: Dictionary) -> void:
	if player_idx == 0:
		_situations[situation_idx]["p1"] = plan
	else:
		_situations[situation_idx]["p2"] = plan

func _round_up_to_10k(value: float) -> int:
	if value <= 0:
		return 0
	return int(ceil(value / 10000.0) * 10000.0)

func _perspective_label(player_idx: int, situation: Dictionary) -> String:
	var owner = situation["owner"]
	if owner == "neutral":
		return "Neutral"
	if owner == _player_key(player_idx):
		return "Home"
	return "Enemy"

func _owner_label(situation: Dictionary) -> String:
	var owner = situation["owner"]
	if owner == "neutral":
		return "Neutral"
	return owner.to_upper()

func _player_key(player_idx: int) -> String:
	return "p1" if player_idx == 0 else "p2"

func _enemy_territory_bonus(player_idx: int) -> int:
	var bonus := 0
	for i in range(_situations.size()):
		var situation = _situations[i]
		if situation["terrain"] == "city":
			continue
		var perspective = _perspective_label(player_idx, situation)
		if perspective != "Enemy":
			continue
		var plan = _get_plan(player_idx, i)
		if plan["divisions"] > 0:
			bonus += enemy_territory_bonus
	return bonus

func _compute_losses(p1_troops: int, p2_troops: int, terrain: String, owner: String) -> Array:
	if p1_troops <= 0 and p2_troops <= 0:
		return [0, 0]
	if p1_troops <= 0 or p2_troops <= 0:
		return [0, 0]
	var ratio := float(max(p1_troops, p2_troops)) / float(min(p1_troops, p2_troops))
	var large_loss := _loss_fraction_large(ratio)
	var small_loss := 1.0 - large_loss
	var p1_loss_frac := large_loss if p1_troops >= p2_troops else small_loss
	var p2_loss_frac := large_loss if p2_troops >= p1_troops else small_loss
	if terrain == "open":
		p1_loss_frac *= 0.5
		p2_loss_frac *= 0.5
	elif terrain == "no_escape":
		if p1_troops < p2_troops:
			p1_loss_frac *= 2.0
		elif p2_troops < p1_troops:
			p2_loss_frac *= 2.0
	elif terrain == "city":
		if owner == "p1":
			p2_loss_frac *= 2.0
		elif owner == "p2":
			p1_loss_frac *= 2.0
	p1_loss_frac = clamp(p1_loss_frac, 0.0, 1.0)
	p2_loss_frac = clamp(p2_loss_frac, 0.0, 1.0)
	return [
		int(round(p1_troops * p1_loss_frac)),
		int(round(p2_troops * p2_loss_frac))
	]

func _snapshot_plans(player_idx: int) -> Array:
	var out := []
	for i in range(_situations.size()):
		var plan = _get_plan(player_idx, i)
		out.append({"divisions": plan["divisions"], "march_type": plan["march_type"]})
	return out

func _apparent_enemy_troops(enemy_idx: int, situation_idx: int) -> String:
	if enemy_idx < 0 or enemy_idx > 1:
		return "Unknown"
	var key = "p1" if enemy_idx == 0 else "p2"
	if situation_idx >= _last_round_plans[key].size():
		return "Unknown"
	var plan = _last_round_plans[key][situation_idx]
	var divisions = int(plan["divisions"])
	if divisions <= 0:
		return "0"
	var visibility = MARCH_TYPES[plan["march_type"]]["visibility"]
	var troops_per_div = float(_last_round_totals[enemy_idx]) / float(troop_divisor_max)
	var apparent = troops_per_div * divisions * visibility
	return "%d" % _round_up_to_10k(apparent)

func _loss_fraction_large(ratio: float) -> float:
	if ratio <= 1.0:
		return 0.5
	if ratio <= 2.0:
		return lerp(0.5, 0.25, (ratio - 1.0) / 1.0)
	if ratio <= 4.0:
		return lerp(0.25, 0.2, (ratio - 2.0) / 2.0)
	return 0.2

func _on_end_turn_pressed() -> void:
	if _awaiting_accept:
		return
	if _awaiting_resolution:
		return
	if _current_player == 1:
		_resolve_turn()
		_current_player = 0
		_awaiting_accept = true
	else:
		_current_player = 1
		_awaiting_accept = true
	_update_display()

func _on_accept_turn_pressed() -> void:
	_awaiting_accept = false
	if _pending_resolution and _pending_resolution_for[_current_player]:
		_begin_resolution_for_current()
	_update_display()

func _on_accept_resolution_pressed() -> void:
	if not _awaiting_resolution:
		return
	_awaiting_resolution = false
	_pending_resolution_for[_current_player] = false
	if not _pending_resolution_for[0] and not _pending_resolution_for[1]:
		_pending_resolution = false
		_last_resolution_lines.clear()
	_update_display()

func _resolve_turn() -> void:
	var losses := [0, 0]
	_last_resolution_lines.clear()
	_last_round_totals = [_players[0]["total_troops"], _players[1]["total_troops"]]
	_last_round_plans = {
		"p1": _snapshot_plans(0),
		"p2": _snapshot_plans(1)
	}
	for i in range(_situations.size()):
		var situation = _situations[i]
		var p1 = _get_plan(0, i)
		var p2 = _get_plan(1, i)
		var p1_troops = _divisions_to_troops(0, p1["divisions"])
		var p2_troops = _divisions_to_troops(1, p2["divisions"])
		var terrain = situation["terrain"]
		if p1["divisions"] > 0 and p2["divisions"] > 0:
			var loss_pair = _compute_losses(p1_troops, p2_troops, terrain, situation["owner"])
			losses[0] += loss_pair[0]
			losses[1] += loss_pair[1]
			_last_resolution_lines.append("%s (%s): P1 %d div vs P2 %d div -> Losses P1 %d, P2 %d." % [
				TERRAIN_LABELS.get(terrain, terrain),
				_owner_label(situation),
				p1["divisions"],
				p2["divisions"],
				loss_pair[0],
				loss_pair[1]
			])
		else:
			if p1["divisions"] > 0 or p2["divisions"] > 0:
				_last_resolution_lines.append("%s (%s): P1 %d div vs P2 %d div (no battle)." % [
					TERRAIN_LABELS.get(terrain, terrain),
					_owner_label(situation),
					p1["divisions"],
					p2["divisions"]
				])
			else:
				_last_resolution_lines.append("%s (%s): no forces present." % [
					TERRAIN_LABELS.get(terrain, terrain),
					_owner_label(situation)
				])
	var old_totals := [_players[0]["total_troops"], _players[1]["total_troops"]]
	var new_totals := [0, 0]
	for player_idx in range(2):
		var bonus = _enemy_territory_bonus(player_idx)
		new_totals[player_idx] = max(0, _players[player_idx]["total_troops"] - losses[player_idx] + bonus)
		_players[player_idx]["total_troops"] = new_totals[player_idx]
		_players[player_idx]["last_losses"] = losses[player_idx]
	_pending_resolution = true
	_pending_resolution_for = [true, true]
	_pending_resolution_data = {"old": old_totals, "new": new_totals}
	for i in range(_situations.size()):
		_situations[i]["revealed"] = [true, true]

func _divisions_to_troops(player_idx: int, divisions: int) -> int:
	if troop_divisor_max <= 0:
		return 0
	var total = float(_players[player_idx]["total_troops"])
	return int(round((total / troop_divisor_max) * divisions))

func _update_agent_state() -> void:
	if not _ensure_agent():
		return
	_agent.set_state_value("current_player", _current_player)
	_agent.set_state_value("awaiting_accept", _awaiting_accept)
	_agent.set_state_value("awaiting_resolution", _awaiting_resolution)
	_agent.set_state_value("pending_resolution", _pending_resolution)
	_agent.set_state_value("situation_count", _situations.size())
	_agent.set_state_value("troops_p1", _players[0]["total_troops"])
	_agent.set_state_value("troops_p2", _players[1]["total_troops"])
	_agent.set_state_value("last_losses_p1", _players[0]["last_losses"])
	_agent.set_state_value("last_losses_p2", _players[1]["last_losses"])
	_agent.set_state_value("plan_divisions_p1", _collect_plan_divisions(0))
	_agent.set_state_value("plan_divisions_p2", _collect_plan_divisions(1))

func _collect_plan_divisions(player_idx: int) -> Array:
	var out := []
	for i in range(_situations.size()):
		var plan = _get_plan(player_idx, i)
		out.append(float(plan["divisions"]))
	return out

func refresh_agent_state() -> void:
	_update_agent_state()

func _ensure_agent() -> bool:
	if _agent != null and _agent.has_method("set_state_value"):
		return true
	_agent = get_node_or_null("/root/AgentTcpServer")
	if _agent == null:
		_agent = get_node_or_null("AgentTcpServer")
	if _agent == null:
		var root := get_tree().get_root()
		if root != null:
			_agent = root.find_child("AgentTcpServer", true, false)
	return _agent != null and _agent.has_method("set_state_value")

func handle_agent_command(name: String, msg: Dictionary) -> Dictionary:
	if name == "game_accept_turn":
		_on_accept_turn_pressed()
		return {"ok": true}
	if name == "game_accept_resolution":
		_on_accept_resolution_pressed()
		return {"ok": true}
	if name == "game_refresh":
		refresh_agent_state()
		return {"ok": true}
	if name == "game_reset":
		_init_game()
		_build_cards()
		_build_plan_list()
		_update_display()
		return {"ok": true}
	if name == "game_add_situation":
		if not msg.has("terrain") or not msg.has("perspective"):
			return {"ok": false, "error": "missing terrain or perspective"}
		var terrain := str(msg["terrain"])
		if not TERRAIN_TYPES.has(terrain):
			return {"ok": false, "error": "invalid terrain"}
		var perspective := str(msg["perspective"])
		var idx = _add_or_get_situation(_current_player, terrain, perspective)
		if idx < 0:
			return {"ok": false, "error": "invalid perspective"}
		_rebuild_situations()
		return {"ok": true, "index": idx}
	if name == "game_end_turn":
		_on_end_turn_pressed()
		return {"ok": true}
	if name == "game_set_plan":
		if not msg.has("terrain"):
			return {"ok": false, "error": "missing terrain"}
		var index := int(msg["terrain"])
		if index < 0 or index >= _situations.size():
			return {"ok": false, "error": "invalid terrain"}
		var divisions := int(msg.get("divisions", 0))
		var march_type := int(msg.get("march_type", 0))
		divisions = clamp(divisions, 0, troop_divisor_max)
		march_type = clamp(march_type, 0, MARCH_TYPES.size() - 1)
		var current_divisions: int = int(_get_plan(_current_player, index)["divisions"])
		var max_allowed: int = _remaining_divisions() + current_divisions
		if divisions > max_allowed:
			divisions = max_allowed
		_set_plan(_current_player, index, {"divisions": divisions, "march_type": march_type})
		_update_display()
		return {"ok": true, "divisions": divisions, "march_type": march_type}
	if name == "game_click_plan_ui":
		if not msg.has("terrain") or not msg.has("target"):
			return {"ok": false, "error": "missing terrain or target"}
		var index := int(msg["terrain"])
		if index < 0 or index >= _plan_cards.size():
			return {"ok": false, "error": "invalid terrain"}
		var target := str(msg["target"])
		var row_data = _plan_rows.get(index, null)
		if row_data == null:
			return {"ok": false, "error": "missing plan row"}
		var plan_card: Node = row_data["plan_card"]
		var ui_viewport: SubViewport = plan_card.get_ui_viewport()
		if ui_viewport == null:
			return {"ok": false, "error": "missing viewport"}
		var row: Control = row_data["row"]
		var pos = _ui_target_center(row_data, target)
		if pos == null:
			return {"ok": false, "error": "unknown target"}
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = pos
		press.global_position = pos
		ui_viewport.push_input(press)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = pos
		release.global_position = pos
		ui_viewport.push_input(release)
		if msg.get("hitmarker", false):
			var world_pos = _ui_target_world(plan_card, pos)
			if world_pos != null:
				var ui_quad: Node3D = plan_card.get_node_or_null("UIQuad")
				if ui_quad != null:
					_show_hit_marker(world_pos, ui_quad.global_basis)
		return {"ok": true}
	if name == "game_hide_hitmarker":
		_hide_hit_marker()
		return {"ok": true}
	return {}

func _ui_target_center(row_data: Dictionary, target: String):
	var control: Control = null
	if target == "minus":
		control = row_data["minus"]
	elif target == "plus":
		control = row_data["plus"]
	elif target == "march":
		control = row_data["march"]
	elif target == "divisions":
		control = row_data["divisions_label"]
	if control == null:
		return null
	var rect := control.get_global_rect()
	return rect.position + (rect.size * 0.5)

func _ui_target_world(plan_card: Node, ui_pos: Vector2):
	if plan_card == null:
		return null
	var viewport_size = plan_card.ui_viewport_size_vec()
	var quad_size = plan_card.ui_quad_size_vec()
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return null
	var u = ui_pos.x / viewport_size.x
	var v = ui_pos.y / viewport_size.y
	var local_x = (u - 0.5) * quad_size.x
	var local_z = (0.5 - v) * quad_size.y
	var ui_quad: Node3D = plan_card.get_node_or_null("UIQuad")
	if ui_quad == null:
		return null
	var local = Vector3(local_x, 0, local_z)
	return ui_quad.to_global(local)

func _update_resolution_overlay() -> void:
	if _resolution_list == null:
		return
	for child in _resolution_list.get_children():
		child.queue_free()
	if not _pending_resolution:
		return
	var old_totals: Array = _pending_resolution_data.get("old", [0, 0])
	var new_totals: Array = _pending_resolution_data.get("new", [0, 0])
	var lines = [
		"Round Results",
		"Player 1: %d -> %d" % [old_totals[0], new_totals[0]],
		"Player 2: %d -> %d" % [old_totals[1], new_totals[1]]
	]
	for line in lines:
		var label := Label.new()
		label.text = str(line)
		_resolution_list.add_child(label)

func _begin_resolution_for_current() -> void:
	_awaiting_resolution = true

func _add_or_get_situation(player_idx: int, terrain: String, perspective: String) -> int:
	var owner := ""
	if perspective == "neutral":
		owner = "neutral"
	elif perspective == "home":
		owner = _player_key(player_idx)
	elif perspective == "enemy":
		owner = _player_key(1 - player_idx)
	else:
		return -1
	for i in range(_situations.size()):
		var s = _situations[i]
		if s["terrain"] == terrain and s["owner"] == owner:
			s["revealed"][player_idx] = true
			return i
	_situations.append({
		"terrain": terrain,
		"owner": owner,
		"p1": {"divisions": 0, "march_type": 0},
		"p2": {"divisions": 0, "march_type": 0},
		"revealed": [player_idx == 0, player_idx == 1]
	})
	return _situations.size() - 1

func _rebuild_situations() -> void:
	_build_cards()
	_build_plan_list()
	_update_display()
