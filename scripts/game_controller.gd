extends Node3D

const MARCH_TYPES := [
	{"name": "🏕️ Normal 1x", "visibility": 1.0},
	{"name": "📣 Noisy 2x", "visibility": 2.0},
	{"name": "🤫 Quiet 0.5x", "visibility": 0.5},
]

const TERRAIN_TYPES := ["open", "difficult", "no_escape", "city"]
const TERRAIN_LABELS := {
	"open": "Open Ground",
	"difficult": "Difficult Ground",
	"no_escape": "No Escape",
	"city": "City"
}
const TERRAIN_COLORS := {
	"open": Color(0.94, 0.9, 0.78),
	"difficult": Color(0.85, 0.85, 0.85),
	"no_escape": Color(0.82, 0.78, 0.76),
	"city": Color(0.78, 0.86, 0.92)
}

@export var troop_divisor_max := 5
@export var starting_troops := 100000
@export var enemy_territory_bonus := 5000

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
var _siege_streaks := [0, 0]
var _winner := -1

var _cards: Array = []
var _card_index_by_key := {}
var _enemy_units_by_card := []

var _units_by_player := [[], []]
var _dragging_unit: Node3D = null
var _drag_offset := Vector3.ZERO
var _drag_plane_y := 0.2

var _hit_marker: MeshInstance3D = null
var _hover_glow: MeshInstance3D = null
var _hovered_card := -1
var _hovered_march_card := -1
var _hovered_march_side := 0
var _hovered_controls_card := -1

@onready var _cards_root: Node3D = $World/CardsRoot
@onready var _unit_pool_root: Node3D = $World/UnitPool
@onready var _camera: Camera3D = $World/Camera3D
@onready var _turn_label: Label = $UI/HUD/HUDBox/TurnLabel
@onready var _troops_label: Label = $UI/HUD/HUDBox/TroopsLabel
@onready var _loss_label: Label = $UI/HUD/HUDBox/LossLabel
@onready var _enemy_troops_label: Label = $UI/HUD/HUDBox/EnemyTroopsLabel
@onready var _end_turn_button: Button = $UI/HUD/EndTurnButton
@onready var _overlay: Control = $UI/TurnOverlay
@onready var _accept_button: Button = $UI/TurnOverlay/AcceptTurnButton
@onready var _accept_label: Label = $UI/TurnOverlay/AcceptTurnLabel
@onready var _resolution_overlay: Control = $UI/ResolutionOverlay
@onready var _resolution_summary: Label = $UI/ResolutionOverlay/ResolutionPanel/MarginContainer/ResolutionBox/ResolutionSummary
@onready var _resolution_you_total: Label = $UI/ResolutionOverlay/ResolutionPanel/MarginContainer/ResolutionBox/ResolutionTotals/YouTotalLabel
@onready var _resolution_they_total: Label = $UI/ResolutionOverlay/ResolutionPanel/MarginContainer/ResolutionBox/ResolutionTotals/TheyTotalLabel
@onready var _resolution_accept: Button = $UI/ResolutionOverlay/ResolutionPanel/MarginContainer/ResolutionBox/ResolutionAcceptButton
@onready var _victory_overlay: Control = $UI/VictoryOverlay
@onready var _victory_label: Label = $UI/VictoryOverlay/VictoryLabel
@onready var _victory_menu_button: Button = $UI/VictoryOverlay/VictoryMenuButton
@onready var _main_menu: Control = $UI/MainMenu
@onready var _menu_play: Button = $UI/MainMenu/MenuBox/PlayButton
@onready var _menu_howto: Button = $UI/MainMenu/MenuBox/HowToPlayButton
@onready var _menu_credits: Button = $UI/MainMenu/MenuBox/CreditsButton
@onready var _menu_quit: Button = $UI/MainMenu/MenuBox/QuitButton
@onready var _howto_screen: Control = $UI/HowToPlay
@onready var _howto_back: Button = $UI/HowToPlay/HowToPanel/HowToMargin/HowToBox/HowToBackButton
@onready var _credits_screen: Control = $UI/Credits
@onready var _credits_back: Button = $UI/Credits/CreditsPanel/CreditsMargin/CreditsBox/CreditsBackButton
@onready var _credits_script: Button = $UI/Credits/CreditsPanel/CreditsMargin/CreditsBox/CreditsScriptButton
@onready var _script_overlay: Control = $UI/ScriptOverlay
@onready var _script_text: TextEdit = $UI/ScriptOverlay/ScriptPanel/ScriptMargin/ScriptBox/ScriptScroll/ScriptText
@onready var _script_close: Button = $UI/ScriptOverlay/ScriptPanel/ScriptMargin/ScriptBox/ScriptCloseButton
@onready var _sfx_player: AudioStreamPlayer = $Audio/SfxPlayer
@onready var _music_player: AudioStreamPlayer = $Audio/MusicPlayer
@onready var _red_land_label: Label3D = $Red/Label3D
@onready var _blue_land_label: Label3D = $Blue/Label3D
@onready var _neutral_land_label: Label3D = $Neutral/Label3D
@onready var _open_terrain_label: Label3D = $"Open Terrain/Label3D"
@onready var _difficult_terrain_label: Label3D = $"Difficult Terrain/Label3D"
@onready var _no_escape_terrain_label: Label3D = $"No Escape Terrain/Label3D"
@onready var _red_city_label: Label3D = $"Red City Label/Label3D"
@onready var _blue_city_label: Label3D = $"Blue City Label/Label3D"

@onready var _row_home_zone: Area3D = $World/HoverZones/RowHomeZone
@onready var _row_neutral_zone: Area3D = $World/HoverZones/RowNeutralZone
@onready var _row_enemy_zone: Area3D = $World/HoverZones/RowEnemyZone
@onready var _col_open_zone: Area3D = $World/HoverZones/ColOpenZone
@onready var _col_difficult_zone: Area3D = $World/HoverZones/ColDifficultZone
@onready var _col_no_escape_zone: Area3D = $World/HoverZones/ColNoEscapeZone
@onready var _col_city_zone: Area3D = $World/HoverZones/ColCityZone
var _agent: Node = null

var _unit_scene := preload("res://scenes/Unit.tscn")
var _sfx_lift := preload("res://resources/Slurp.wav")
var _sfx_place := preload("res://resources/Knock.wav")
var _sfx_next_turn := preload("res://resources/NextTurn.wav")
var _sfx_life_points := preload("res://resources/LifePoints.wav")
var _sfx_victory := preload("res://resources/Victory.wav")
var _sfx_click: AudioStream = null
var _sfx_card_hover: AudioStream = null
var _music_intro := preload("res://resources/Morgana Rides.mp3")
const _SFX_CLICK_PATH := "res://resources/Click.wav"
const _SFX_CARD_HOVER_PATH := "res://resources/CardHover.wav"
const _CITY_LABEL_DEFEND := "┌ Defend Your Capital ┐\n"
const _CITY_LABEL_ATTACK := "Win or Occupy \nEnemy Capital for\n ┌ 3 Turns to Win ┐\n"

var _label_base_sizes: Dictionary = {}
var _label_base_positions: Dictionary = {}
var _hover_row_key := ""
var _hover_col_key := ""
var _hover_label_boost := 3
var _hover_label_y := 0.02
var _resolution_tween: Tween = null
var _ui_blocked := false

func _ready() -> void:
	add_to_group("game_controller")
	_gather_cards()
	_init_game()
	_build_unit_pool()
	_cache_label_sizes()
	_update_display()
	_load_click_sfx()
	_load_card_hover_sfx()
	_play_music_start()
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_accept_button.pressed.connect(_on_accept_turn_pressed)
	_resolution_accept.pressed.connect(_on_accept_resolution_pressed)
	if _victory_menu_button != null:
		_victory_menu_button.pressed.connect(_on_menu_back)
	_menu_play.pressed.connect(_on_menu_play)
	_menu_howto.pressed.connect(_on_menu_howto)
	_menu_credits.pressed.connect(_on_menu_credits)
	_menu_quit.pressed.connect(_on_menu_quit)
	_howto_back.pressed.connect(_on_menu_back)
	_credits_back.pressed.connect(_on_menu_back)
	_credits_script.pressed.connect(_on_menu_script)
	_script_close.pressed.connect(_on_menu_script_close)
	if _agent != null and _agent.has_method("set_game_controller"):
		_agent.set_game_controller(self)
	_update_agent_state()
	set_process(true)
	set_process_input(true)
	_build_hit_marker()
	_hover_glow = $World/HoverGlow
	if _hover_glow != null:
		_hover_glow.visible = false
	if _should_skip_main_menu():
		_start_game_from_menu()
	else:
		_show_main_menu()

func _should_skip_main_menu() -> bool:
	var args = OS.get_cmdline_args()
	return args.has("--skip-main-menu")

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

func _process(_delta: float) -> void:
	pass

func _input(event: InputEvent) -> void:
	if _ui_blocked:
		return
	if _awaiting_accept or _awaiting_resolution:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _try_cycle_march(event.position):
					return
				if _try_start_unit_drag(event.position):
					return
			else:
				if _dragging_unit != null:
					_end_unit_drag(event.position)
					return
	if event is InputEventMouseMotion:
		if _dragging_unit != null:
			_update_unit_drag(event.position)
			return
		_update_march_hover(event.position)
		_update_controls_hover(event.position)
		_update_row_col_hover(event.position)
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_update_card_hover(event.position)

func _try_cycle_march(mouse_pos: Vector2) -> bool:
	var hit = _raycast(mouse_pos, 8)
	if hit.is_empty():
		return false
	var collider = hit.get("collider", null)
	if collider == null or not (collider is Area3D):
		return false
	var card = _find_card_for_node(collider)
	if card == null or not card.has_meta("situation_index"):
		return false
	var idx: int = int(card.get_meta("situation_index"))
	var plan = _get_plan(_current_player, idx)
	if int(plan["divisions"]) <= 0:
		return false
	var dir := 0
	if collider == card.get_march_left_area():
		dir = -1
	elif collider == card.get_march_right_area():
		dir = 1
	if dir == 0:
		return false
	var next = int(plan["march_type"]) + dir
	if next < 0:
		next = MARCH_TYPES.size() - 1
	if next >= MARCH_TYPES.size():
		next = 0
	plan["march_type"] = next
	_set_plan(_current_player, idx, plan)
	_play_sfx(_sfx_click)
	_update_display()
	return true

func _find_card_for_node(node: Node) -> Node:
	var current: Node = node
	while current != null:
		if current.has_method("get_card_area"):
			return current
		current = current.get_parent()
	return null

func _try_start_unit_drag(mouse_pos: Vector2) -> bool:
	var hit = _raycast(mouse_pos, 4)
	if hit.is_empty():
		return false
	var collider = hit.get("collider", null)
	if collider == null or not (collider is Area3D):
		return false
	var unit: Node3D = collider.get_parent()
	if unit == null or not unit.is_in_group("unit_token"):
		return false
	if not unit.draggable:
		return false
	_dragging_unit = unit
	_drag_plane_y = unit.global_position.y
	_drag_offset = Vector3.ZERO
	unit.lift_visual(unit.drag_lift)
	if unit.has_method("set_dragging"):
		unit.set_dragging(true)
	_play_sfx(_sfx_lift)
	_clear_controls_hover()
	_clear_march_hover()
	_update_display()
	return true

func _update_unit_drag(mouse_pos: Vector2) -> void:
	if _dragging_unit == null:
		return
	var ray_origin = _camera.project_ray_origin(mouse_pos)
	var ray_dir = _camera.project_ray_normal(mouse_pos)
	var hit_pos = _ray_plane_intersect(ray_origin, ray_dir, _drag_plane_y)
	if hit_pos == null:
		return
	_dragging_unit.global_position = hit_pos
	_update_card_hover(mouse_pos)

func _end_unit_drag(mouse_pos: Vector2) -> void:
	if _dragging_unit == null:
		return
	var unit = _dragging_unit
	_dragging_unit = null
	if unit != null:
		unit.lift_visual(0.0)
		if unit.has_method("set_dragging"):
			unit.set_dragging(false)
	_clear_card_hover()
	var hit = _raycast(mouse_pos, 2)
	if hit.is_empty():
		_assign_unit_to_home(unit)
		_play_sfx(_sfx_place)
		_update_display()
		return
	var collider = hit.get("collider", null)
	if collider == null or not (collider is Area3D):
		_assign_unit_to_home(unit)
		_play_sfx(_sfx_place)
		_update_display()
		return
	var card: Node = collider.get_parent()
	if card == null or not card.has_meta("situation_index"):
		_assign_unit_to_home(unit)
		_play_sfx(_sfx_place)
		_update_display()
		return
	var idx: int = int(card.get_meta("situation_index"))
	_assign_unit_to_situation(unit, idx)
	_play_sfx(_sfx_place)
	_update_display()

func _update_card_hover(mouse_pos: Vector2) -> void:
	if _hover_glow == null:
		return
	if _dragging_unit == null:
		_clear_card_hover()
		return
	var hit = _raycast(mouse_pos, 2)
	if hit.is_empty():
		_clear_card_hover()
		return
	var collider = hit.get("collider", null)
	if collider == null or not (collider is Area3D):
		_clear_card_hover()
		return
	var card: Node = collider.get_parent()
	if card == null or not card.has_meta("situation_index"):
		_clear_card_hover()
		return
	var idx: int = int(card.get_meta("situation_index"))
	if idx != _hovered_card:
		_hovered_card = idx
		_play_sfx(_sfx_card_hover)
	var offset = Vector3(0, 0.05, 0)
	_hover_glow.global_basis = card.global_basis * Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	_hover_glow.global_position = card.global_position + offset
	_set_hover_glow_visible(true)

func _clear_card_hover() -> void:
	_hovered_card = -1
	_set_hover_glow_visible(false)

func _update_march_hover(mouse_pos: Vector2) -> void:
	var hit = _raycast(mouse_pos, 8)
	if hit.is_empty():
		_clear_march_hover()
		return
	var collider = hit.get("collider", null)
	if collider == null or not (collider is Area3D):
		_clear_march_hover()
		return
	var card = _find_card_for_node(collider)
	if card == null or not card.has_meta("situation_index"):
		_clear_march_hover()
		return
	var idx: int = int(card.get_meta("situation_index"))
	var plan = _get_plan(_current_player, idx)
	if int(plan["divisions"]) <= 0 or not card.visible:
		_clear_march_hover()
		return
	var side := 0
	if collider == card.get_march_left_area():
		side = -1
	elif collider == card.get_march_right_area():
		side = 1
	if side == 0:
		_clear_march_hover()
		return
	if _hovered_march_card != idx or _hovered_march_side != side:
		_clear_march_hover()
		_hovered_march_card = idx
		_hovered_march_side = side
	card.set_arrow_hover(side == -1, side == 1)

func _clear_march_hover() -> void:
	if _hovered_march_card >= 0 and _hovered_march_card < _cards.size():
		_cards[_hovered_march_card].set_arrow_hover(false, false)
	_hovered_march_card = -1
	_hovered_march_side = 0

func _update_controls_hover(mouse_pos: Vector2) -> void:
	if _dragging_unit != null:
		_clear_controls_hover()
		return
	var hit = _raycast(mouse_pos, 2)
	if hit.is_empty():
		_clear_controls_hover()
		return
	var collider = hit.get("collider", null)
	if collider == null or not (collider is Area3D):
		_clear_controls_hover()
		return
	var card = _find_card_for_node(collider)
	if card == null or not card.has_meta("situation_index"):
		_clear_controls_hover()
		return
	var idx: int = int(card.get_meta("situation_index"))
	var plan = _get_plan(_current_player, idx)
	if int(plan["divisions"]) <= 0:
		_clear_controls_hover()
		return
	if _hovered_controls_card != idx:
		_clear_controls_hover()
		_hovered_controls_card = idx
		_update_display()

func _clear_controls_hover() -> void:
	if _hovered_controls_card == -1:
		return
	var prev = _hovered_controls_card
	_hovered_controls_card = -1
	if prev >= 0 and prev < _cards.size():
		_cards[prev].set_arrows_visible(false)
	_update_display()

func _cache_label_sizes() -> void:
	_label_base_sizes.clear()
	_label_base_positions.clear()
	var labels = [
		_red_land_label,
		_blue_land_label,
		_neutral_land_label,
		_open_terrain_label,
		_difficult_terrain_label,
		_no_escape_terrain_label,
		_red_city_label,
		_blue_city_label
	]
	for label in labels:
		if label != null:
			_label_base_sizes[label] = label.font_size
			_label_base_positions[label] = label.position

func _set_label_hover(label: Label3D, hover: bool) -> void:
	if label == null or not _label_base_sizes.has(label):
		return
	var base: int = int(_label_base_sizes[label])
	label.font_size = base + (_hover_label_boost if hover else 0)
	if _label_base_positions.has(label):
		var base_pos: Vector3 = _label_base_positions[label]
		label.position = base_pos + (Vector3(0, _hover_label_y, 0) if hover else Vector3.ZERO)

func _update_row_col_hover(mouse_pos: Vector2) -> void:
	var row_key := ""
	var col_key := ""
	var row_hit = _raycast(mouse_pos, 16)
	if not row_hit.is_empty():
		var row_collider = row_hit.get("collider", null)
		if row_collider == _row_home_zone:
			row_key = "home"
		elif row_collider == _row_neutral_zone:
			row_key = "neutral"
		elif row_collider == _row_enemy_zone:
			row_key = "enemy"
	var col_hit = _raycast(mouse_pos, 32)
	if not col_hit.is_empty():
		var col_collider = col_hit.get("collider", null)
		if col_collider == _col_open_zone:
			col_key = "open"
		elif col_collider == _col_difficult_zone:
			col_key = "difficult"
		elif col_collider == _col_no_escape_zone:
			col_key = "no_escape"
		elif col_collider == _col_city_zone:
			col_key = "city"
	if row_key == _hover_row_key and col_key == _hover_col_key:
		return
	_hover_row_key = row_key
	_hover_col_key = col_key
	_set_label_hover(_blue_land_label, row_key == ("home" if _current_player == 0 else "enemy"))
	_set_label_hover(_red_land_label, row_key == ("enemy" if _current_player == 0 else "home"))
	_set_label_hover(_neutral_land_label, row_key == "neutral")
	_set_label_hover(_open_terrain_label, col_key == "open")
	_set_label_hover(_difficult_terrain_label, col_key == "difficult")
	_set_label_hover(_no_escape_terrain_label, col_key == "no_escape")
	_set_label_hover(_blue_city_label, col_key == "city")
	_set_label_hover(_red_city_label, col_key == "city")

func _ray_plane_intersect(ray_origin: Vector3, ray_dir: Vector3, plane_y: float) -> Variant:
	var denom = ray_dir.y
	if abs(denom) < 0.0001:
		return null
	var t = (plane_y - ray_origin.y) / denom
	if t < 0.0:
		return null
	return ray_origin + ray_dir * t

func _raycast(mouse_pos: Vector2, mask: int) -> Dictionary:
	var from = _camera.project_ray_origin(mouse_pos)
	var dir = _camera.project_ray_normal(mouse_pos)
	var space = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = mask
	return space.intersect_ray(params)

func _show_hit_marker(world_pos: Vector3, basis: Basis) -> void:
	if _hit_marker == null:
		return
	_hit_marker.global_position = world_pos
	_hit_marker.global_basis = basis
	_hit_marker.visible = true

func _hide_hit_marker() -> void:
	if _hit_marker != null:
		_hit_marker.visible = false

func _on_unit_lifted(_unit: Node3D) -> void:
	_play_sfx(_sfx_lift)

func _on_ui_click_sfx() -> void:
	_play_sfx(_sfx_click)

func _load_click_sfx() -> void:
	if _sfx_click != null:
		return
	_sfx_click = ResourceLoader.load(_SFX_CLICK_PATH)

func _load_card_hover_sfx() -> void:
	if _sfx_card_hover != null:
		return
	_sfx_card_hover = ResourceLoader.load(_SFX_CARD_HOVER_PATH)

func _set_hover_glow_visible(enabled: bool) -> void:
	if _hover_glow == null:
		return
	if Engine.is_editor_hint():
		return
	var mat := _hover_glow.material_override
	if mat is StandardMaterial3D:
		var color = _player_color(_current_player)
		mat.albedo_color = Color(color.r, color.g, color.b, 0.35)
		mat.emission = color
	_hover_glow.visible = enabled

func _play_sfx(stream: AudioStream) -> void:
	if _sfx_player == null or stream == null:
		return
	_sfx_player.stop()
	_sfx_player.stream = stream
	_sfx_player.play()

func _play_music_start() -> void:
	if _music_player == null or _music_intro == null:
		return
	if _music_intro is AudioStreamMP3:
		_music_intro.loop = true
	elif _music_intro.has_property("loop"):
		_music_intro.set("loop", true)
	_music_player.stop()
	_music_player.stream = _music_intro
	_music_player.play()

func _init_game() -> void:
	_players = []
	for i in range(2):
		_players.append({
			"total_troops": starting_troops,
			"last_losses": 0
		})
	_situations = []
	_card_index_by_key.clear()
	_current_player = 0
	_awaiting_accept = false
	_awaiting_resolution = false
	_last_resolution_lines.clear()
	_last_round_totals = [_players[0]["total_troops"], _players[1]["total_troops"]]
	_last_round_plans = {"p1": [], "p2": []}
	_siege_streaks = [0, 0]
	_winner = -1
	_init_situations_from_cards()

func _gather_cards() -> void:
	_cards.clear()
	_enemy_units_by_card.clear()
	var found: Array = []
	for child in _cards_root.get_children():
		if child != null and child.has_method("get_card_area"):
			found.append(child)
	found.sort_custom(func(a, b): return int(a.situation_index) < int(b.situation_index))
	for card in found:
		_cards.append(card)
		var idx = int(card.situation_index)
		card.set_meta("situation_index", idx)
		var card_area: Area3D = card.get_card_area()
		if card_area != null:
			card_area.collision_layer = 2
			card_area.collision_mask = 2
			card_area.input_ray_pickable = true
		_build_enemy_units(idx, card)

func _init_situations_from_cards() -> void:
	if _cards.is_empty():
		return
	var max_index := 0
	for card in _cards:
		max_index = max(max_index, int(card.situation_index))
	_situations = []
	_situations.resize(max_index + 1)
	for card in _cards:
		var idx = int(card.situation_index)
		var terrain = str(card.terrain)
		var owner = str(card.owner_key)
		_situations[idx] = {
			"terrain": terrain,
			"owner": owner,
			"p1": {"divisions": 0, "march_type": 0},
			"p2": {"divisions": 0, "march_type": 0}
		}
		_card_index_by_key[_situation_key(terrain, owner)] = idx

func _build_enemy_units(index: int, card: Node) -> void:
	var units := []
	var enemy_root := Node3D.new()
	enemy_root.name = "EnemyUnits"
	card.add_child(enemy_root)
	for i in range(troop_divisor_max):
		var unit = _unit_scene.instantiate()
		enemy_root.add_child(unit)
		unit.set_unit_owner(1, Color(0.85, 0.3, 0.3))
		unit.set_draggable(false)
		unit.visible = false
		units.append(unit)
	_enemy_units_by_card.append(units)

func _build_unit_pool() -> void:
	for player_idx in range(2):
		_units_by_player[player_idx].clear()
	if _unit_pool_root == null:
		_unit_pool_root = Node3D.new()
		_unit_pool_root.name = "UnitPool"
		$World.add_child(_unit_pool_root)
	for child in _unit_pool_root.get_children():
		if child != null and child.is_in_group("unit_token"):
			var owner = _normalize_unit_owner(child)
			if owner < 0 or owner > 1:
				owner = 0
			child.owner_id = owner
			_units_by_player[owner].append(child)
	for player_idx in range(2):
		if _units_by_player[player_idx].size() > troop_divisor_max:
			var extras = _units_by_player[player_idx].slice(troop_divisor_max)
			for unit in extras:
				if unit != null:
					unit.queue_free()
			_units_by_player[player_idx] = _units_by_player[player_idx].slice(0, troop_divisor_max)
		while _units_by_player[player_idx].size() < troop_divisor_max:
			var unit = _unit_scene.instantiate()
			unit.name = "Unit_%d_%d" % [player_idx, _units_by_player[player_idx].size()]
			_unit_pool_root.add_child(unit)
			unit.owner_id = player_idx
			_units_by_player[player_idx].append(unit)
	for player_idx in range(2):
		for unit in _units_by_player[player_idx]:
			unit.set_unit_owner(player_idx, _player_color(player_idx))
			if int(unit.assigned_situation) < 0:
				unit.assigned_situation = _home_city_index(player_idx)
			unit.set_draggable(player_idx == _current_player)
			if not unit.is_connected("lifted", Callable(self, "_on_unit_lifted")):
				unit.lifted.connect(_on_unit_lifted)
	_sync_divisions_from_units(0)
	_sync_divisions_from_units(1)

func _normalize_unit_owner(unit: Node) -> int:
	if unit == null:
		return 0
	if unit.name.find("_P2_") != -1 or unit.name.find("_p2_") != -1:
		return 1
	if unit.name.find("_P1_") != -1 or unit.name.find("_p1_") != -1:
		return 0
	if unit.has_method("get"):
		var value = unit.get("owner_id")
		if typeof(value) == TYPE_INT:
			return int(value)
	return 0

func _update_display() -> void:
	var show_hud = not _ui_blocked
	$UI/HUD.visible = show_hud
	if not show_hud:
		_overlay.visible = false
		_resolution_overlay.visible = false
		_victory_overlay.visible = false
	var player_name = "Blue Player" if _current_player == 0 else "Red Player"
	_turn_label.text = "%s Turn" % player_name
	_turn_label.add_theme_color_override("font_color", _player_color(_current_player))
	if _accept_label != null:
		_accept_label.text = "%s Turn" % player_name
		_accept_label.add_theme_color_override("font_color", _player_color(_current_player))
	_update_land_labels()
	_update_city_labels()
	var total_troops: int = _players[_current_player]["total_troops"]
	_troops_label.text = "Total Troops: %d" % total_troops
	var enemy_idx = 1 - _current_player
	_enemy_troops_label.text = "Enemy Troops: %d" % _players[enemy_idx]["total_troops"]
	_loss_label.text = "Losses Last Turn: %d" % _players[_current_player]["last_losses"]
	for i in range(_situations.size()):
		_update_card(i)
	_update_unit_visibility()
	_update_unit_positions()
	_update_enemy_units()
	_overlay.visible = _awaiting_accept
	var show_victory = _winner >= 0
	_resolution_overlay.visible = _awaiting_resolution and not show_victory
	_victory_overlay.visible = show_victory
	if show_victory and _victory_label != null:
		_victory_label.text = "BLUE VICTORY" if _winner == 0 else "RED VICTORY"
		_victory_label.add_theme_color_override("font_color", _player_color(_winner))
		_play_victory()
	_update_agent_state()
	_update_resolution_overlay()

func _play_victory() -> void:
	if _winner < 0:
		return
	if _music_player != null and _music_player.playing:
		_music_player.stop()
	_play_sfx(_sfx_victory)

func _update_land_labels() -> void:
	if _red_land_label == null or _blue_land_label == null or _neutral_land_label == null:
		return
	var blue_home = _current_player == 0
	var enemy_bonus_text = "+%dk per controlled\n" % int(enemy_territory_bonus / 1000)
	var blue_text = ("┌ Homelands ┐\n" if blue_home else "┌ Enemy Lands ┐\n") + (enemy_bonus_text if not blue_home else "")
	var red_text = ("┌ Enemy Lands ┐\n" if blue_home else "┌ Homelands ┐\n") + (enemy_bonus_text if blue_home else "")
	_blue_land_label.text = blue_text
	_red_land_label.text = red_text
	_neutral_land_label.text = "┌ Neutral Lands ┐\n"

func _update_city_labels() -> void:
	if _red_city_label == null or _blue_city_label == null:
		return
	var blue_home = _current_player == 0
	var enemy_idx = 1 - _current_player
	var turns_to_win = max(0, 3 - _siege_streaks[_current_player])
	var turns_to_lose = max(0, 3 - _siege_streaks[enemy_idx])
	var defend_text = "┌ Defend Your Capital ┐\n"
	if _siege_streaks[enemy_idx] > 0:
		defend_text += "%d Turns Until Loss\n" % turns_to_lose
	var attack_text = "Win or Occupy \nEnemy Capital for\n ┌ %d Turns to Win ┐\n" % turns_to_win
	if blue_home:
		_blue_city_label.text = defend_text
		_red_city_label.text = attack_text
	else:
		_blue_city_label.text = attack_text
		_red_city_label.text = defend_text

func _update_card(index: int) -> void:
	var situation = _situations[index]
	var enemy_idx = 1 - _current_player
	var perspective := _perspective_label(_current_player, situation)
	var terrain_label: String = str(TERRAIN_LABELS.get(situation["terrain"], situation["terrain"]))
	var apparent := _apparent_enemy_troops(enemy_idx, index)
	var apparentShorthand := str(int(apparent)/1000) + "K"
	var plan = _get_plan(_current_player, index)
	var divisions = int(plan["divisions"])
	var troops = _divisions_to_troops(_current_player, divisions)
	var troopsShorthand := str(int(troops)/1000) + "K"
	var march_name = MARCH_TYPES[plan["march_type"]]["name"]
	var text := ""
	if (int(troops) > 0):
		text += "%s " % [
			troopsShorthand,
		]
	if (int(apparent) > 0):
		if (int(troops) == 0):
			text += "0 "
		text += "vs. %s" % [
			apparentShorthand
		]
		
	_cards[index].set_text(text)
	_cards[index].set_march_label(march_name)
	var show_controls = divisions > 0 and not _awaiting_accept and not _awaiting_resolution
	_cards[index].set_march_controls_visible(show_controls)
	var show_arrows = show_controls and _hovered_controls_card == index and _dragging_unit == null
	_cards[index].set_arrows_visible(show_arrows)

func _update_unit_visibility() -> void:
	for player_idx in range(2):
		for unit in _units_by_player[player_idx]:
			if unit == null:
				continue
			var should_show = player_idx == _current_player and not _awaiting_accept and not _awaiting_resolution
			unit.visible = should_show
			unit.set_draggable(should_show)

func _update_unit_positions() -> void:
	for player_idx in range(2):
		_update_units_for_player(player_idx)

func _update_units_for_player(player_idx: int) -> void:
	if _units_by_player[player_idx].is_empty():
		return
	var assignments := {}
	for unit in _units_by_player[player_idx]:
		var idx = int(unit.assigned_situation)
		if not assignments.has(idx):
			assignments[idx] = []
		assignments[idx].append(unit)
	for situation_idx in assignments.keys():
		var units: Array = assignments[situation_idx]
		var target_idx = situation_idx
		if target_idx < 0:
			target_idx = _home_city_index(player_idx)
		if target_idx < 0 or target_idx >= _cards.size():
			continue
		var card = _cards[target_idx]
		var anchor: Node3D = card.get_own_units_anchor()
		_layout_units_on_anchor(units, anchor)

func _layout_units_on_anchor(units: Array, anchor: Node3D) -> void:
	if anchor == null:
		return
	var columns = 5
	var spacing = 0.22
	for i in range(units.size()):
		var unit: Node3D = units[i]
		var row = int(i / columns)
		var col = i % columns
		var offset_x = (float(col) - float(columns - 1) / 2.0) * spacing
		var offset_z = float(row) * spacing
		var local = Vector3(offset_x, 0.0, offset_z)
		unit.global_position = anchor.to_global(local)

func _update_enemy_units() -> void:
	var enemy_idx = 1 - _current_player
	for i in range(_situations.size()):
		var units: Array = _enemy_units_by_card[i]
		for unit in units:
			if unit != null:
				unit.set_unit_owner(enemy_idx, _player_color(enemy_idx))
		var count = _apparent_enemy_divisions(enemy_idx, i)
		count = clamp(count, 0, troop_divisor_max)
		for j in range(units.size()):
			var unit: Node3D = units[j]
			unit.visible = j < count and not _awaiting_accept and not _awaiting_resolution
		if count <= 0:
			continue
		var card = _cards[i]
		var anchor: Node3D = card.get_enemy_units_anchor()
		_layout_units_on_anchor(units.slice(0, count), anchor)

func _player_color(player_idx: int) -> Color:
	if player_idx == 0:
		return Color(0.3, 0.6, 0.9)
	return Color(0.85, 0.3, 0.3)

func _assign_unit_to_situation(unit: Node3D, situation_idx: int) -> void:
	unit.assigned_situation = situation_idx
	_sync_divisions_from_units(unit.owner_id)

func _assign_unit_to_home(unit: Node3D) -> void:
	var home_idx = _home_city_index(unit.owner_id)
	unit.assigned_situation = home_idx
	_sync_divisions_from_units(unit.owner_id)

func _sync_divisions_from_units(player_idx: int) -> void:
	var counts := []
	for i in range(_situations.size()):
		counts.append(0)
	for unit in _units_by_player[player_idx]:
		var idx = int(unit.assigned_situation)
		if idx >= 0 and idx < counts.size():
			counts[idx] += 1
	for i in range(_situations.size()):
		var plan = _get_plan(player_idx, i)
		plan["divisions"] = counts[i]
		_set_plan(player_idx, i, plan)

func _home_city_index(player_idx: int) -> int:
	var owner = _player_key(player_idx)
	var key = _situation_key("city", owner)
	if _card_index_by_key.has(key):
		return int(_card_index_by_key[key])
	return -1

func _situation_key(terrain: String, owner: String) -> String:
	return "%s|%s" % [terrain, owner]

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

func _update_siege_streaks() -> void:
	var city_p1 = _card_index_by_key.get(_situation_key("city", "p1"), -1)
	var city_p2 = _card_index_by_key.get(_situation_key("city", "p2"), -1)
	_siege_streaks[0] = _next_siege_streak(0, city_p2)
	_siege_streaks[1] = _next_siege_streak(1, city_p1)
	for player_idx in range(2):
		if _siege_streaks[player_idx] >= 3:
			_winner = player_idx

func _next_siege_streak(player_idx: int, city_index: int) -> int:
	if city_index < 0 or city_index >= _situations.size():
		return 0
	var attacker_plan = _get_plan(player_idx, city_index)
	var defender_idx = 1 - player_idx
	var defender_plan = _get_plan(defender_idx, city_index)
	if int(attacker_plan["divisions"]) <= 0:
		return 0
	if int(defender_plan["divisions"]) <= 0:
		return _siege_streaks[player_idx] + 1
	var attacker_troops = _divisions_to_troops(player_idx, attacker_plan["divisions"])
	var defender_troops = _divisions_to_troops(defender_idx, defender_plan["divisions"])
	if attacker_troops > defender_troops:
		return _siege_streaks[player_idx] + 1
	return 0

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
		return "0"
	var plan = _last_round_plans[key][situation_idx]
	var divisions = int(plan["divisions"])
	if divisions <= 0:
		return "0"
	var visibility = MARCH_TYPES[plan["march_type"]]["visibility"]
	var troops_per_div = float(_last_round_totals[enemy_idx]) / float(troop_divisor_max)
	var apparent = troops_per_div * divisions * visibility
	return "%d" % _round_up_to_10k(apparent)

func _apparent_enemy_divisions(enemy_idx: int, situation_idx: int) -> int:
	if enemy_idx < 0 or enemy_idx > 1:
		return 0
	var key = "p1" if enemy_idx == 0 else "p2"
	if situation_idx >= _last_round_plans[key].size():
		return 0
	var plan = _last_round_plans[key][situation_idx]
	var divisions = int(plan["divisions"])
	if divisions <= 0:
		return 0
	var visibility = MARCH_TYPES[plan["march_type"]]["visibility"]
	var troops_per_div = float(_last_round_totals[enemy_idx]) / float(troop_divisor_max)
	var apparent = troops_per_div * divisions * visibility
	var apparent_troops = _round_up_to_10k(apparent)
	if troops_per_div <= 0:
		return 0
	return int(ceil(float(apparent_troops) / troops_per_div))

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
	_play_sfx(_sfx_next_turn)
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
	_play_sfx(_sfx_next_turn)
	if _pending_resolution and _pending_resolution_for[_current_player]:
		_begin_resolution_for_current()
	_update_display()

func _on_accept_resolution_pressed() -> void:
	if not _awaiting_resolution:
		return
	_play_sfx(_sfx_next_turn)
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
	_update_siege_streaks()
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
	var bonus_totals := [0, 0]
	for player_idx in range(2):
		var bonus = _enemy_territory_bonus(player_idx)
		bonus_totals[player_idx] = bonus
		new_totals[player_idx] = max(0, _players[player_idx]["total_troops"] - losses[player_idx] + bonus)
		_players[player_idx]["total_troops"] = new_totals[player_idx]
		_players[player_idx]["last_losses"] = losses[player_idx]
	_pending_resolution = true
	_pending_resolution_for = [true, true]
	_pending_resolution_data = {"old": old_totals, "new": new_totals, "bonus": bonus_totals}

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
		_gather_cards()
		_init_game()
		_build_unit_pool()
		_update_display()
		return {"ok": true}
	if name == "game_end_turn":
		_on_end_turn_pressed()
		return {"ok": true}
	if name == "game_set_march":
		if not msg.has("terrain"):
			return {"ok": false, "error": "missing terrain"}
		var index := int(msg["terrain"])
		if index < 0 or index >= _situations.size():
			return {"ok": false, "error": "invalid terrain"}
		var march_type := int(msg.get("march_type", 0))
		march_type = clamp(march_type, 0, MARCH_TYPES.size() - 1)
		var plan = _get_plan(_current_player, index)
		plan["march_type"] = march_type
		_set_plan(_current_player, index, plan)
		_update_display()
		return {"ok": true, "march_type": march_type}
	if name == "game_assign_unit":
		if not msg.has("unit"):
			return {"ok": false, "error": "missing unit"}
		if not msg.has("situation"):
			return {"ok": false, "error": "missing situation"}
		var unit_idx := int(msg["unit"])
		if unit_idx < 0 or unit_idx >= _units_by_player[_current_player].size():
			return {"ok": false, "error": "invalid unit"}
		var situation_idx := int(msg["situation"])
		if situation_idx < 0 or situation_idx >= _situations.size():
			return {"ok": false, "error": "invalid situation"}
		_assign_unit_to_situation(_units_by_player[_current_player][unit_idx], situation_idx)
		_update_display()
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
		var units = _units_by_player[_current_player]
		var home_idx = _home_city_index(_current_player)
		for i in range(units.size()):
			if i < divisions:
				units[i].assigned_situation = index
			else:
				units[i].assigned_situation = home_idx
		_sync_divisions_from_units(_current_player)
		var plan = _get_plan(_current_player, index)
		plan["march_type"] = march_type
		_set_plan(_current_player, index, plan)
		_update_display()
		return {"ok": true, "divisions": divisions, "march_type": march_type}
	if name == "game_click_plan_ui":
		return {"ok": false, "error": "plan UI click no longer supported"}
	if name == "game_hide_hitmarker":
		_hide_hit_marker()
		return {"ok": true}
	return {}

func _update_resolution_overlay() -> void:
	if _resolution_summary == null or _resolution_you_total == null or _resolution_they_total == null:
		return
	if not _pending_resolution:
		return
	var bonus_totals: Array = _pending_resolution_data.get("bonus", [0, 0])
	var you_idx = _current_player
	var they_idx = 1 - _current_player
	var you_lost = _players[you_idx]["last_losses"]
	var they_lost = _players[they_idx]["last_losses"]
	_resolution_summary.text = "You killed %d of their troops and lost %d. You stole %d troops." % [
		they_lost,
		you_lost,
		bonus_totals[you_idx]
	]
	_resolution_you_total.add_theme_color_override("font_color", _player_color(you_idx))
	_resolution_they_total.add_theme_color_override("font_color", _player_color(they_idx))

func _begin_resolution_for_current() -> void:
	_awaiting_resolution = true
	if _winner < 0:
		_start_resolution_animation()

func _show_main_menu() -> void:
	_ui_blocked = true
	_main_menu.visible = true
	_howto_screen.visible = false
	_credits_screen.visible = false
	_script_overlay.visible = false
	_update_display()

func _start_game_from_menu() -> void:
	_ui_blocked = false
	_main_menu.visible = false
	_howto_screen.visible = false
	_credits_screen.visible = false
	_script_overlay.visible = false
	_update_display()

func _show_howto() -> void:
	_ui_blocked = true
	_main_menu.visible = false
	_howto_screen.visible = true
	_credits_screen.visible = false
	_script_overlay.visible = false
	_update_display()

func _show_credits() -> void:
	_ui_blocked = true
	_main_menu.visible = false
	_howto_screen.visible = false
	_credits_screen.visible = true
	_script_overlay.visible = false
	_update_display()

func _show_script_overlay() -> void:
	_ui_blocked = true
	_script_overlay.visible = true
	if _script_text != null:
		var file = FileAccess.open("res://script.txt", FileAccess.READ)
		if file != null:
			_script_text.text = file.get_as_text()
			file.close()
		else:
			_script_text.text = "Failed to load script.txt"
	_update_display()

func _hide_script_overlay() -> void:
	_script_overlay.visible = false
	_update_display()

func _on_menu_play() -> void:
	_start_game_from_menu()

func _on_menu_howto() -> void:
	_show_howto()

func _on_menu_credits() -> void:
	_show_credits()

func _on_menu_quit() -> void:
	get_tree().quit()

func _on_menu_back() -> void:
	_gather_cards()
	_init_game()
	_build_unit_pool()
	_reset_units_to_home()
	_cache_label_sizes()
	_winner = -1
	_update_display()
	_show_main_menu()

func _reset_units_to_home() -> void:
	for player_idx in range(2):
		var home_idx = _home_city_index(player_idx)
		for unit in _units_by_player[player_idx]:
			if unit != null:
				unit.assigned_situation = home_idx
	_sync_divisions_from_units(0)
	_sync_divisions_from_units(1)
	_update_unit_positions()

func _on_menu_script() -> void:
	_show_script_overlay()

func _on_menu_script_close() -> void:
	_hide_script_overlay()

func _start_resolution_animation() -> void:
	if _resolution_accept == null or _resolution_you_total == null or _resolution_they_total == null:
		return
	if _resolution_tween != null:
		_resolution_tween.kill()
	var old_totals: Array = _pending_resolution_data.get("old", [0, 0])
	var new_totals: Array = _pending_resolution_data.get("new", [0, 0])
	var you_idx = _current_player
	var they_idx = 1 - _current_player
	var no_change = int(old_totals[0]) == int(new_totals[0]) and int(old_totals[1]) == int(new_totals[1])
	_set_total_label(_resolution_you_total, "You", int(old_totals[you_idx]))
	_set_total_label(_resolution_they_total, "They", int(old_totals[they_idx]))
	if no_change:
		_resolution_accept.visible = true
		_resolution_accept.disabled = false
		return
	_resolution_accept.visible = false
	_resolution_accept.disabled = true
	_set_total_label(_resolution_you_total, "You", int(old_totals[you_idx]))
	_set_total_label(_resolution_they_total, "They", int(old_totals[they_idx]))
	_resolution_tween = create_tween()
	var duration := 1.5
	_resolution_tween.tween_interval(0.5)
	_resolution_tween.tween_callback(Callable(self, "_play_sfx").bind(_sfx_life_points))
	_resolution_tween.tween_method(
		Callable(self, "_tween_total_label").bind(_resolution_you_total, "You"),
		float(old_totals[you_idx]),
		float(new_totals[you_idx]),
		duration
	)
	_resolution_tween.parallel().tween_method(
		Callable(self, "_tween_total_label").bind(_resolution_they_total, "Them"),
		float(old_totals[they_idx]),
		float(new_totals[they_idx]),
		duration
	)
	_resolution_tween.finished.connect(_on_resolution_animation_finished)

func _tween_total_label(value: float, label: Label, prefix: String) -> void:
	_set_total_label(label, prefix, int(round(value)))

func _set_total_label(label: Label, prefix: String, value: int) -> void:
	if label == null:
		return
	label.text = "%s: %d" % [prefix, value]

func _on_resolution_animation_finished() -> void:
	if _resolution_accept == null:
		return
	_resolution_accept.visible = true
	_resolution_accept.disabled = false
