extends Node3D

@export var card_size := Vector2(2.6, 1.6)
@export var card_thickness := 0.08
@export var card_color := Color(0.92, 0.88, 0.78)

@onready var _mesh: MeshInstance3D = $CardMesh
@onready var _label: Label3D = $Label3D

func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(card_size.x, card_thickness, card_size.y)
	_mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = card_color
	material.roughness = 0.9
	material.metallic = 0.0
	_mesh.material_override = material
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.font_size = 24
	_label.modulate = Color(0.12, 0.1, 0.08)
	_label.pixel_size = 0.01
	_label.rotation_degrees.x = -90.0
	_label.no_depth_test = false
	_label.render_priority = 0
	# Place text on the top face, slightly inset from the top-left.
	_label.position = Vector3(-card_size.x * 0.48, (card_thickness * 0.5) + 0.002, -card_size.y * 0.45)

func set_text(text: String) -> void:
	_label.text = text

func set_card_color(color: Color) -> void:
	card_color = color
	if _mesh == null:
		return
	if _mesh.material_override is StandardMaterial3D:
		_mesh.material_override.albedo_color = card_color
