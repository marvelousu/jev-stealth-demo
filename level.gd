extends Node3D

## Purely presentational level construction for the first Jev stealth prototype.
## `obstacles` is deliberately the only source for solid cover/walls: main.gd uses
## the same rectangles for its circle-vs-AABB collision, sight, and grid navigation.

var camera: Camera3D
var obstacles: Array[Rect2] = []
var case_visual: Node3D
var generator_visual: Node3D

const FLOOR_SIZE := Vector2(30.0, 20.0)
const FLOOR_CENTER := Vector3(0.0, -0.16, 0.0)
const NIGHT_BLUE := Color("#07131f")
const STEEL := Color("#263847")
const STEEL_DARK := Color("#17242f")
const CONCRETE := Color("#3d4c54")
const HAZARD_YELLOW := Color("#f2b84b")
const CYAN := Color("#4fd8e8")


func _ready() -> void:
	name = "RelayStationLevel"
	_build_environment()
	_build_floor()
	_define_and_build_obstacles()
	_build_nonblocking_dressing()
	_build_objective_props()
	_build_lighting()
	_build_camera()


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "NightAtmosphere"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = NIGHT_BLUE
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#7a9fc1")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var moon := DirectionalLight3D.new()
	moon.name = "CoolMoonlight"
	moon.rotation_degrees = Vector3(-58.0, -28.0, 0.0)
	moon.light_color = Color("#8bbde0")
	moon.light_energy = 0.8
	moon.shadow_enabled = true
	add_child(moon)


func _build_floor() -> void:
	var concrete := _material(Color("#26353d"), Color("#0d161c"), 0.04)
	_add_box("Floor", Vector3(FLOOR_SIZE.x, 0.24, FLOOR_SIZE.y), FLOOR_CENTER, concrete)

	# Painted strips establish patrol lanes without pretending to be collision geometry.
	for x in [-13.0, -7.0, 0.0, 7.0, 13.0]:
		_add_box("Decorative_Nonblocking_LaneStripe", Vector3(0.14, 0.018, 18.5), Vector3(x, -0.025, 0.0), _material(Color("#5a6870")))
	for z in [-8.2, 0.0, 8.2]:
		_add_box("Decorative_Nonblocking_CrossStripe", Vector3(28.5, 0.018, 0.12), Vector3(0.0, -0.024, z), _material(Color("#34444d")))

	# Two yellow approach lanes point to the southern extraction gates.
	for x in [-11.0, 11.0]:
		_add_box("Decorative_Nonblocking_ExitStripe", Vector3(1.8, 0.024, 5.2), Vector3(x, -0.018, 7.1), _material(HAZARD_YELLOW, HAZARD_YELLOW, 0.12))


func _define_and_build_obstacles() -> void:
	# Perimeter. The gaps at x=-11 and x=11 on the z=+ side are extraction gates.
	_add_obstacle(Rect2(-15.0, -10.0, 30.0, 0.45), 1.6, STEEL_DARK, "North Perimeter")
	_add_obstacle(Rect2(-15.0, 9.55, 2.2, 0.45), 1.6, STEEL_DARK, "South Perimeter West")
	_add_obstacle(Rect2(-8.7, 9.55, 17.4, 0.45), 1.6, STEEL_DARK, "South Perimeter Centre")
	_add_obstacle(Rect2(13.3, 9.55, 1.7, 0.45), 1.6, STEEL_DARK, "South Perimeter East")
	_add_obstacle(Rect2(-15.0, -10.0, 0.45, 19.0), 1.6, STEEL_DARK, "West Perimeter")
	_add_obstacle(Rect2(14.55, -10.0, 0.45, 19.0), 1.6, STEEL_DARK, "East Perimeter")

	# The north rooms are walls, rather than filled blocks. Their interiors contain the
	# case, generator, and guard C, while the wide southern doorways make each reachable.
	# NE storage interior: x 7.90..12.10, z -8.10..-4.90; doorway x 9.05..10.95.
	_add_obstacle(Rect2(7.45, -8.55, 5.1, 0.45), 1.35, STEEL, "Northeast Storage North Wall")
	_add_obstacle(Rect2(7.45, -8.55, 0.45, 4.55), 1.35, STEEL, "Northeast Storage West Wall")
	_add_obstacle(Rect2(12.10, -8.55, 0.45, 4.55), 1.35, STEEL, "Northeast Storage East Wall")
	_add_obstacle(Rect2(7.45, -4.45, 1.60, 0.45), 1.35, STEEL, "Northeast Storage Door Left")
	_add_obstacle(Rect2(10.95, -4.45, 1.60, 0.45), 1.35, STEEL, "Northeast Storage Door Right")

	# NW equipment interior: x -12.20..-7.80, z -7.80..-5.00; doorway x -11.20..-8.80.
	_add_obstacle(Rect2(-12.65, -8.25, 5.3, 0.45), 1.45, STEEL, "Northwest Equipment North Wall")
	_add_obstacle(Rect2(-12.65, -8.25, 0.45, 3.75), 1.45, STEEL, "Northwest Equipment West Wall")
	_add_obstacle(Rect2(-7.80, -8.25, 0.45, 3.75), 1.45, STEEL, "Northwest Equipment East Wall")
	_add_obstacle(Rect2(-12.65, -4.95, 1.45, 0.45), 1.45, STEEL, "Northwest Equipment Door Left")
	_add_obstacle(Rect2(-8.80, -4.95, 1.45, 0.45), 1.45, STEEL, "Northwest Equipment Door Right")

	# Low cover breaks sightlines and allows the player to demonstrate flanking.
	_add_obstacle(Rect2(-3.0, -1.05, 5.15, 1.05), 1.1, CONCRETE, "Central Blast Cover")
	_add_obstacle(Rect2(4.45, 2.1, 2.15, 2.15), 1.15, STEEL, "East Crates")
	_add_obstacle(Rect2(-7.15, 3.6, 2.5, 1.25), 1.05, CONCRETE, "West Barrier")
	_add_obstacle(Rect2(-0.8, 5.6, 2.25, 1.15), 1.0, STEEL, "South Cable Cover")
	_add_obstacle(Rect2(8.1, 6.15, 2.15, 1.2), 1.05, CONCRETE, "South East Barrier")


func _add_obstacle(rect: Rect2, height: float, color: Color, label: String) -> void:
	obstacles.append(rect)
	var center := Vector3(rect.position.x + rect.size.x * 0.5, height * 0.5, rect.position.y + rect.size.y * 0.5)
	var root := Node3D.new()
	root.name = "Solid_%s" % label.replace(" ", "_")
	root.set_meta("collision_source", "obstacles")
	add_child(root)
	var body := _add_box("BlockingCover", Vector3(rect.size.x, height, rect.size.y), center, _material(color))
	body.reparent(root)
	body.global_position = center

	# A thinner top inset gives the solid cover a readable low-poly silhouette.
	var lip_size := Vector3(maxf(0.2, rect.size.x - 0.18), 0.11, maxf(0.2, rect.size.y - 0.18))
	var lip := _add_box("BlockingCoverTop", lip_size, center + Vector3(0.0, height * 0.5 + 0.055, 0.0), _material(color.lightened(0.18)))
	lip.reparent(root)
	lip.global_position = center + Vector3(0.0, height * 0.5 + 0.055, 0.0)

	# Wall-mounted hazard bars help show which geometry blocks routes, without adding
	# separate unreported solid objects.
	if rect.size.x > 3.0:
		var bar := _add_box("BlockingCoverHazardBar", Vector3(rect.size.x * 0.42, 0.10, 0.025), center + Vector3(0.0, 0.2, rect.size.y * 0.5 + 0.014), _material(HAZARD_YELLOW, HAZARD_YELLOW, 0.18))
		bar.reparent(root)
		bar.global_position = center + Vector3(0.0, 0.2, rect.size.y * 0.5 + 0.014)


func _build_nonblocking_dressing() -> void:
	# These objects are named and tagged as decorative. They have no collision/nav data.
	for position in [Vector3(-13.6, 0.0, -7.8), Vector3(13.6, 0.0, -7.8), Vector3(-13.6, 0.0, 7.6), Vector3(13.6, 0.0, 7.6)]:
		_add_lamp(position, CYAN)
	for position in [Vector3(-6.0, 0.0, -3.4), Vector3(6.3, 0.0, -3.0), Vector3(0.0, 0.0, 3.9)]:
		_add_lamp(position, Color("#ff9e58"))

	_add_sign(Vector3(0.0, 3.0, -9.2), "第七中継所  //  RELAY STATION 07", Color("#a8eaf4"), 0.014)
	_add_sign(Vector3(-11.0, 2.0, 9.12), "出口 A", HAZARD_YELLOW, 0.012)
	_add_sign(Vector3(11.0, 2.0, 9.12), "出口 B", HAZARD_YELLOW, 0.012)

	# Small glowing conduits make the storage/equipment zones legible from the camera.
	for x in [-11.6, -10.6, -9.6, 8.7, 9.7, 10.7, 11.7]:
		var z := -8.78 if x < 0.0 else -3.72
		_add_box("Decorative_Nonblocking_Conduit", Vector3(0.34, 0.12, 0.34), Vector3(x, 0.12, z), _material(CYAN, CYAN, 0.45))


func _build_objective_props() -> void:
	case_visual = Node3D.new()
	case_visual.name = "ObjectiveCase"
	case_visual.position = Vector3(10.0, 0.0, -6.0)
	add_child(case_visual)
	var case_body := _add_box("CaseBody", Vector3(0.78, 0.34, 0.53), case_visual.global_position + Vector3(0.0, 0.35, 0.0), _material(Color("#d7a44c"), HAZARD_YELLOW, 0.18))
	case_body.reparent(case_visual)
	case_body.position = Vector3(0.0, 0.35, 0.0)
	var case_handle := _add_box("CaseHandle", Vector3(0.36, 0.10, 0.12), case_visual.global_position + Vector3(0.0, 0.59, 0.0), _material(Color("#161d23")))
	case_handle.reparent(case_visual)
	case_handle.position = Vector3(0.0, 0.59, 0.0)
	_add_sign_to(case_visual, Vector3(0.0, 1.0, 0.0), "ケース / E長押し", HAZARD_YELLOW, 0.009)

	generator_visual = Node3D.new()
	generator_visual.name = "RelayGenerator"
	generator_visual.position = Vector3(-10.0, 0.0, -6.0)
	add_child(generator_visual)
	var core := _add_cylinder("GeneratorCore", 0.68, 1.55, Vector3(-10.0, 0.78, -6.0), _material(Color("#34515b")))
	core.reparent(generator_visual)
	core.position = Vector3(0.0, 0.78, 0.0)
	var generator_light := OmniLight3D.new()
	generator_light.name = "GeneratorStatusLight"
	generator_light.position = Vector3(0.0, 1.4, 0.0)
	generator_light.light_color = CYAN
	generator_light.light_energy = 1.4
	generator_light.omni_range = 3.2
	generator_visual.add_child(generator_light)
	_add_sign_to(generator_visual, Vector3(0.0, 2.0, 0.0), "無線電源 / E", CYAN, 0.009)


func _build_lighting() -> void:
	for data in [
		[Vector3(-10.0, 5.0, -4.0), CYAN],
		[Vector3(10.0, 5.0, -4.0), Color("#9dd6ff")],
		[Vector3(-6.0, 4.6, 5.8), Color("#ffad72")],
		[Vector3(6.5, 4.6, 5.8), CYAN],
		[Vector3(0.0, 5.5, 0.0), Color("#cfecff")],
	]:
		var light := OmniLight3D.new()
		light.name = "IndustrialFillLight"
		light.position = data[0]
		light.light_color = data[1]
		light.light_energy = 1.45
		light.omni_range = 10.5
		add_child(light)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "TacticalCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28.0
	camera.h_offset = 4.4
	camera.near = 0.1
	camera.far = 100.0
	camera.position = Vector3(0.0, 27.0, 24.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -0.2), Vector3.UP)
	camera.current = true


func make_actor(color: Color, label: String) -> Node3D:
	var actor := Node3D.new()
	actor.name = "ActorVisual_%s" % label.replace(" ", "_")
	# Root is at ground; default Godot forward is -Z, so a weapon at -Z makes the
	# facing direction evident to the player and does not require a rotated parent.
	var uniform := _material(color)
	var dark := _material(color.darkened(0.42))
	var head := _material(Color("#d4b49b"))
	var torso := _add_box("Body", Vector3(0.56, 0.82, 0.34), Vector3(0.0, 1.12, 0.0), uniform)
	torso.reparent(actor)
	torso.position = Vector3(0.0, 1.12, 0.0)
	var actor_head := _add_sphere("Head", 0.26, Vector3(0.0, 1.77, -0.02), head)
	actor_head.reparent(actor)
	actor_head.position = Vector3(0.0, 1.77, -0.02)
	for x in [-0.20, 0.20]:
		var leg := _add_box("Leg", Vector3(0.16, 0.62, 0.18), Vector3(x, 0.36, 0.02), dark)
		leg.reparent(actor)
		leg.position = Vector3(x, 0.36, 0.02)
	var weapon := _add_box("Weapon_FacingMinusZ", Vector3(0.13, 0.14, 0.72), Vector3(0.23, 1.16, -0.44), _material(Color("#111820")))
	weapon.reparent(actor)
	weapon.position = Vector3(0.23, 1.16, -0.44)
	var visor := _add_box("Visor_FacingMinusZ", Vector3(0.32, 0.09, 0.04), Vector3(0.0, 1.80, -0.255), _material(CYAN, CYAN, 0.25))
	visor.reparent(actor)
	visor.position = Vector3(0.0, 1.80, -0.255)
	_add_sign_to(actor, Vector3(0.0, 2.55, 0.0), label, Color.WHITE, 0.016, "RoleLabel")
	return actor


func make_ring(color: Color, radius: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "AwarenessRing"
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.05, radius - 0.045)
	torus.outer_radius = radius
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = _material(color, color, 0.5)
	return ring


func _add_lamp(position: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.name = "Decorative_Nonblocking_Lamp"
	root.position = position
	root.set_meta("nonblocking", true)
	add_child(root)
	var pole := _add_cylinder("LampPole", 0.06, 3.3, position + Vector3(0.0, 1.65, 0.0), _material(Color("#1a252d")))
	pole.reparent(root)
	pole.position = Vector3(0.0, 1.65, 0.0)
	var lamp := _add_box("LampGlow", Vector3(0.42, 0.16, 0.42), position + Vector3(0.0, 3.22, 0.0), _material(color, color, 0.8))
	lamp.reparent(root)
	lamp.position = Vector3(0.0, 3.22, 0.0)


func _add_sign(position: Vector3, content: String, color: Color, pixel_size: float) -> void:
	_add_sign_to(self, position, content, color, pixel_size)


func _add_sign_to(parent: Node3D, local_position: Vector3, content: String, color: Color, pixel_size: float, node_name: String = "Decorative_Nonblocking_Sign") -> void:
	var sign := Label3D.new()
	sign.name = node_name
	sign.text = content
	sign.position = local_position
	sign.pixel_size = pixel_size
	sign.modulate = color
	sign.outline_size = 2
	sign.outline_modulate = Color("#07131f")
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.no_depth_test = true
	sign.set_meta("nonblocking", true)
	parent.add_child(sign)


func _add_box(node_name: String, size: Vector3, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	instance.position = position
	add_child(instance)
	return instance


func _add_cylinder(node_name: String, radius: float, height: float, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 10
	instance.mesh = cylinder
	instance.material_override = material
	instance.position = position
	add_child(instance)
	return instance


func _add_sphere(node_name: String, radius: float, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	instance.mesh = sphere
	instance.material_override = material
	instance.position = position
	add_child(instance)
	return instance


func _material(color: Color, emission_color: Color = Color.TRANSPARENT, emission_energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.25
	material.roughness = 0.72
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_energy_multiplier = emission_energy
	return material
