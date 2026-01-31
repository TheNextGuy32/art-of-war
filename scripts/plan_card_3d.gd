extends Node3D

@export var card_size := Vector2(2.6, 1.6)
@export var card_thickness := 0.08
@export var card_color := Color(0.85, 0.9, 0.98)
@export var ui_quad_size := Vector2(2.4, 0.9)
@export var ui_viewport_size := Vector2i(1280, 420)
@export var ui_hit_height := 0.6

@onready var _card_mesh: MeshInstance3D = $CardMesh
@onready var _label: Label3D = $Label3D
@onready var _ui_quad: MeshInstance3D = $UIQuad
@onready var _ui_viewport: SubViewport = $UIViewport
@onready var _ui_root: Control = $UIViewport/UIRoot
@onready var _ui_area: Area3D = $UIArea
@onready var _ui_collision: CollisionShape3D = $UIArea/CollisionShape3D

func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(card_size.x, card_thickness, card_size.y)
	_card_mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = card_color
	material.roughness = 0.9
	material.metallic = 0.0
	_card_mesh.material_override = material
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.font_size = 24
	_label.modulate = Color(0.12, 0.1, 0.08)
	_label.pixel_size = 0.01
	_label.rotation_degrees.x = -90.0
	_label.position = Vector3(-card_size.x * 0.48, (card_thickness * 0.5) + 0.002, card_size.y * 0.45)
	_setup_ui_surface()

func _setup_ui_surface() -> void:
	_ui_viewport.disable_3d = true
	_ui_viewport.size = ui_viewport_size
	_ui_viewport.gui_disable_input = false
	_ui_viewport.transparent_bg = false
	_ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var quad := QuadMesh.new()
	quad.size = ui_quad_size
	_ui_quad.mesh = quad
	_ui_quad.position = Vector3(0, (card_thickness * 0.5) + 0.002, 0.0)
	_ui_quad.rotation_degrees.x = -90.0
	var ui_material := StandardMaterial3D.new()
	ui_material.albedo_texture = _ui_viewport.get_texture()
	ui_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ui_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ui_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_ui_quad.material_override = ui_material
	var shape := BoxShape3D.new()
	shape.size = Vector3(ui_quad_size.x, ui_hit_height, ui_quad_size.y)
	_ui_collision.shape = shape
	_ui_area.position = _ui_quad.position
	_ui_area.rotation_degrees = _ui_quad.rotation_degrees
	_ui_area.collision_layer = 1
	_ui_area.collision_mask = 1
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.size = Vector2(ui_viewport_size.x, ui_viewport_size.y)
	if _ui_root.get_node_or_null("BG") == null:
		var bg := ColorRect.new()
		bg.name = "BG"
		bg.color = Color(0.12, 0.12, 0.14, 1.0)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.size = Vector2(ui_viewport_size.x, ui_viewport_size.y)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui_root.add_child(bg)
		_ui_root.move_child(bg, 0)

func set_text(text: String) -> void:
	_label.text = text

func set_card_color(color: Color) -> void:
	card_color = color
	if _card_mesh.material_override is StandardMaterial3D:
		_card_mesh.material_override.albedo_color = card_color

func get_ui_root() -> Control:
	return _ui_root

func get_ui_viewport() -> SubViewport:
	return _ui_viewport

func get_ui_area() -> Area3D:
	return _ui_area

func ui_viewport_size_vec() -> Vector2:
	return Vector2(ui_viewport_size.x, ui_viewport_size.y)

func ui_quad_size_vec() -> Vector2:
	return ui_quad_size

func ui_quad_to_viewport(local_pos: Vector3) -> Vector2:
	var u = (local_pos.x / ui_quad_size.x) + 0.5
	var v = (local_pos.z / ui_quad_size.y) + 0.5
	u = clamp(u, 0.0, 1.0)
	v = clamp(v, 0.0, 1.0)
	return Vector2(u * ui_viewport_size.x, v * ui_viewport_size.y)

func ui_quad_local_from_ray(ray_origin: Vector3, ray_dir: Vector3) -> Vector3:
	var plane_origin = _ui_quad.global_position
	var plane_normal = _ui_quad.global_transform.basis.y.normalized()
	var denom = plane_normal.dot(ray_dir)
	if abs(denom) < 0.0001:
		return _ui_quad.to_local(ray_origin)
	var t = plane_normal.dot(plane_origin - ray_origin) / denom
	var intersect = ray_origin + (ray_dir * t)
	return _ui_quad.to_local(intersect)
