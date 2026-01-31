extends Node3D

@export var card_size := Vector2(2.6, 1.6)
@export var card_thickness := 0.08
@export var card_color := Color(0.92, 0.88, 0.78)

@onready var _mesh: MeshInstance3D = $CardMesh
@onready var _label: Label3D = $Label3D

func _ready() -> void:
	if _mesh.mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3(card_size.x, card_thickness, card_size.y)
		_mesh.mesh = box
	if _mesh.material_override == null:
		var material := StandardMaterial3D.new()
		material.albedo_color = card_color
		material.roughness = 0.9
		material.metallic = 0.0
		_mesh.material_override = material
	_label.no_depth_test = false
	_label.render_priority = 0
	# Position is configured in the scene for editor-friendly layout.

func set_text(text: String) -> void:
	_label.text = text

func set_card_color(color: Color) -> void:
	card_color = color
	if _mesh == null:
		return
	if _mesh.material_override is StandardMaterial3D:
		_mesh.material_override.albedo_color = card_color
