@tool
extends Node3D

@export var card_size := Vector2(2.6, 1.6)
@export var card_thickness := 0.08
@export var card_color := Color(0.85, 0.9, 0.98)
@export var situation_index := 0
@export var terrain := "open"
@export var owner_key := "neutral"

@onready var _card_mesh: MeshInstance3D = $CardMesh
@onready var _label: Label3D = $Label3D
@onready var _card_area: Area3D = $CardArea
@onready var _card_collision: CollisionShape3D = $CardArea/CardCollision
@onready var _own_units_anchor: Node3D = $OwnUnitsAnchor
@onready var _enemy_units_anchor: Node3D = $EnemyUnitsAnchor
@onready var _march_controls: Node3D = $MarchControls
@onready var _march_label: Label3D = $MarchControls/MarchLabel
@onready var _march_left: Area3D = $MarchControls/LeftArrow
@onready var _march_right: Area3D = $MarchControls/RightArrow
@onready var _march_left_label: Label3D = $MarchControls/LeftArrow/LeftLabel
@onready var _march_right_label: Label3D = $MarchControls/RightArrow/RightLabel

var _arrow_font_base := 32
var _arrow_font_hover := 110
var _arrows_visible := false

func _ready() -> void:
	if _card_mesh.mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3(card_size.x, card_thickness, card_size.y)
		_card_mesh.mesh = box
	if _card_mesh.material_override == null:
		var material := StandardMaterial3D.new()
		material.albedo_color = card_color
		material.roughness = 0.9
		material.metallic = 0.0
		_card_mesh.material_override = material
	# Position is configured in the scene for editor-friendly layout.
	if _card_area != null:
		_card_area.collision_layer = 2
		_card_area.collision_mask = 2
		_card_area.input_ray_pickable = true
	if _march_left != null:
		_march_left.input_ray_pickable = true
	if _march_right != null:
		_march_right.input_ray_pickable = true
	if _march_left_label != null:
		_arrow_font_base = _march_left_label.font_size
	if _march_right_label != null:
		_arrow_font_base = min(_arrow_font_base, _march_right_label.font_size)
	_set_arrows_visible(false)
	_set_arrow_hover(false, false)

func set_text(text: String) -> void:
	if _label != null:
		_label.text = text

func set_march_label(text: String) -> void:
	if _march_label != null:
		_march_label.text = text

func set_card_color(color: Color) -> void:
	card_color = color
	if _card_mesh.material_override is StandardMaterial3D:
		_card_mesh.material_override.albedo_color = card_color

func get_card_area() -> Area3D:
	return _card_area

func get_own_units_anchor() -> Node3D:
	return _own_units_anchor

func get_enemy_units_anchor() -> Node3D:
	return _enemy_units_anchor

func get_march_left_area() -> Area3D:
	return _march_left

func get_march_right_area() -> Area3D:
	return _march_right

func set_march_controls_visible(visible: bool) -> void:
	if _march_controls != null:
		_march_controls.visible = visible

func set_arrows_visible(visible: bool) -> void:
	_set_arrows_visible(visible)

func set_arrow_hover(left: bool, right: bool) -> void:
	_set_arrow_hover(left, right)

func _set_arrow_hover(left: bool, right: bool) -> void:
	if _march_left_label != null:
		_march_left_label.font_size = _arrow_font_hover if left else _arrow_font_base
	if _march_right_label != null:
		_march_right_label.font_size = _arrow_font_hover if right else _arrow_font_base

func _set_arrows_visible(visible: bool) -> void:
	_arrows_visible = visible
	if _march_left != null:
		_march_left.visible = visible
	if _march_right != null:
		_march_right.visible = visible
