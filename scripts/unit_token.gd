@tool
extends Node3D

@export var hover_lift := 0.22
@export var drag_lift := 0.12
@export var token_scale := Vector3(0.16, 0.16, 0.16)
@export var hover_tint := Color(1.0, 1.0, 1.0)
@export var owner_id := 0
@export var assigned_situation := -1

var draggable := true

signal lifted(unit: Node3D)

@onready var _visual: Node3D = $unit
@onready var _area: Area3D = $HitArea
@onready var _base_visual_pos: Vector3 = Vector3.ZERO
@onready var _mesh_instances: Array[MeshInstance3D] = []

func _ready() -> void:
	add_to_group("unit_token")
	if _visual != null:
		_base_visual_pos = _visual.position
		_visual.scale = token_scale
	_collect_meshes()
	if _area != null:
		_area.collision_layer = 4
		_area.collision_mask = 4
		_area.input_ray_pickable = true
		_area.mouse_entered.connect(_on_mouse_entered)
		_area.mouse_exited.connect(_on_mouse_exited)
	set_process(true)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_pos = camera.global_position
	var target = Vector3(cam_pos.x, global_position.y, cam_pos.z)
	look_at(target, Vector3.UP)

func _collect_meshes() -> void:
	_mesh_instances.clear()
	if _visual == null:
		return
	var stack: Array[Node] = [_visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			_mesh_instances.append(node)
		for child in node.get_children():
			if child is Node:
				stack.append(child)

func set_unit_owner(new_owner: int, color: Color) -> void:
	owner_id = new_owner
	set_tint(color)

func set_draggable(value: bool) -> void:
	draggable = value
	if _area != null:
		_area.input_ray_pickable = draggable

func set_tint(color: Color) -> void:
	for mesh in _mesh_instances:
		var mat: StandardMaterial3D = null
		if mesh.material_override is StandardMaterial3D:
			mat = mesh.material_override
		else:
			mat = StandardMaterial3D.new()
			mesh.material_override = mat
		mat.albedo_color = color

func lift_visual(amount: float) -> void:
	if _visual == null:
		return
	_visual.position = _base_visual_pos + Vector3(0, amount, 0)

func _on_mouse_entered() -> void:
	if not draggable:
		return
	lift_visual(hover_lift)
	emit_signal("lifted", self)

func _on_mouse_exited() -> void:
	if not draggable:
		return
	lift_visual(0.0)
