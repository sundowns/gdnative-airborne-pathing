extends Spatial
class_name AirborneNavigationMap

class NavMapCell:
	var is_traversable: bool
	var is_occluded: bool
	var indices: Vector3
	var debug_mesh_instance: MeshInstance
	var point_origin: Vector3
	var neighbours: Array
	func _init(_indices: Vector3, _point_origin: Vector3):
		self.is_traversable = true
		self.is_occluded = false
		self.indices = _indices
		self.point_origin = _point_origin
		self.neighbours = []
	func set_as_occluded():
		self.is_occluded = true
	func set_debug_mesh(mesh: Mesh):
		if self.debug_mesh_instance:
			self.debug_mesh_instance.mesh = mesh
	func set_not_traversable():
		self.is_traversable = false
		if self.debug_mesh_instance:
			self.debug_mesh_instance.queue_free()
			self.debug_mesh_instance = null
	func add_neighbour(neighbour_indices: Vector3):
		neighbours.append(neighbour_indices)
	func clear_references():
		neighbours.clear()
		if debug_mesh_instance:
			debug_mesh_instance.mesh = null
			debug_mesh_instance.free()

class SearchCell:
	var cell: NavMapCell
	var score: float
	func _init(_cell: NavMapCell, _score: float):
		cell = _cell
		score = _score

class ScoreSorter:
	static func sort_ascending_score(a: SearchCell, b: SearchCell):
		if a.score < b.score:
			return true
		return false

export(float) var step_size := 5.0
export(float) var point_geometry_collision_margin := 1.0
export(bool) var check_neighbours_line_of_sight := true
export(int, LAYERS_3D_PHYSICS) var world_collision_mask

onready var top_left_back: Vector3 = $TopLeftBackAnchor.global_transform.origin
onready var bottom_right_front: Vector3 = $BottomRightFrontAnchor.global_transform.origin

var grid: Array = []
# Float dimensions of the 3D nav grid in game-space
var grid_dimensions: Vector3 = Vector3.ZERO
# Integer dimensions (cell counts)
var cell_dimensions: Vector3 = Vector3.ZERO
var cell_centre_offset: Vector3

# Debug vars
enum DebugDrawModes {
	NEIGHBOURS = 0,
	OCCLUSION = 1
}
export(DebugDrawModes) var debug_draw_mode
export(Gradient) var debug_neighbours_gradient: Gradient = preload("res://test_scenes/debug_rainbow_gradient.tres")
export(bool) var is_debug := false
var debug_meshes: Dictionary = {}
var debug_point_mesh: Mesh

var generation_thread: Thread
var generation_mutex: Mutex
var is_nav_mesh_ready: bool = false
const maximum_path_calculation_duration := 20
# warning-ignore:unused_signal
signal navmesh_generated

func _ready():
# warning-ignore:return_value_discarded
	connect("navmesh_generated", self, "_on_navmesh_generated", [], CONNECT_DEFERRED)
	if is_debug:
		generate_debug_point_mesh()
		generate_debug_coloured_meshes()
	generate_grid()
	generation_thread = Thread.new()
	generation_mutex = Mutex.new()
# warning-ignore:return_value_discarded
	generation_thread.start(self, "create_nav_mesh", null)

func generate_grid():
	grid_dimensions = Vector3(abs(top_left_back.x - bottom_right_front.x), abs(top_left_back.y - bottom_right_front.y), abs(top_left_back.z - bottom_right_front.z))
	cell_dimensions = Vector3(floor(grid_dimensions.x / step_size), floor(grid_dimensions.y / step_size), floor(grid_dimensions.z / step_size))
	cell_centre_offset = Vector3(step_size / 2, -step_size / 2, step_size / 2)
	grid = build_nav_grid(cell_dimensions)

func _on_navmesh_generated():
	print("Finished generating airborne nav mesh")
	is_nav_mesh_ready = true
	generation_thread.wait_to_finish()
	generation_thread = null
	if is_debug:
		var debug_node = Node.new()
		debug_node.name = "DEBUG"
		add_child(debug_node)
		populate_debug_point_meshes()

## GENERATION METHODS
func create_nav_mesh(_userdata):
	generation_mutex.lock()
	check_for_geometry_collisions()
#	adjust_occluded_points() # TODO: optionally we can do this to move more outside geometry (to make things move neatly around things)
	remove_occluded_points()
	calculate_neighbouring_cells()
	generation_mutex.unlock()
	emit_signal("navmesh_generated")
	return true

func build_nav_grid(dimensions: Vector3):
	var new_grid = []
	new_grid.resize(dimensions.y)
	for y in range(len(new_grid)):
		var deck = []
		deck.resize(dimensions.x)
		for x in range(len(deck)):
			var row = []
			row.resize(dimensions.z)
			for z in range(len(row)):
				var indices = Vector3(x,y,z)
				row[z] = NavMapCell.new(indices, get_cell_centre(indices))
			deck[x] = row
		new_grid[y] = deck
	return new_grid

# Shapecast to see if we're clipping a wall
func check_for_geometry_collisions():
	var max_results := 1
	var current_game_space := get_world().direct_space_state
	var cast_shape: BoxShape = BoxShape.new()
	cast_shape.extents = Vector3(point_geometry_collision_margin/2, point_geometry_collision_margin/2, point_geometry_collision_margin/2)
	var cast_shape_query := PhysicsShapeQueryParameters.new()
	cast_shape_query.collision_mask = world_collision_mask
	cast_shape_query.set_shape(cast_shape)
	for y in range(len(grid)):
		for x in range(len(grid[y])):
			for z in range(len(grid[y][x])):
				var cell: NavMapCell = get_cell(Vector3(x,y,z))
				var cell_transform = Transform.IDENTITY
				cell_transform.origin = get_cell_centre(cell.indices)
				cast_shape_query.transform = cell_transform
				var cast_result = current_game_space.intersect_shape(cast_shape_query, max_results)
				if cast_result:
					cell.set_as_occluded()
					if is_debug and debug_draw_mode == DebugDrawModes.OCCLUSION:
						cell.set_debug_mesh(debug_meshes["HIGHLIGHT"])

func remove_occluded_points():
	for y in range(len(grid)):
		for x in range(len(grid[y])):
			for z in range(len(grid[y][x])):
				var cell: NavMapCell = get_cell(Vector3(x,y,z))
				if cell.is_occluded:
					cell.set_not_traversable()

func calculate_neighbouring_cells():
	var current_game_space := get_world().direct_space_state
	for y in range(len(grid)):
		for x in range(len(grid[y])):
			for z in range(len(grid[y][x])):
				var cell: NavMapCell = get_cell(Vector3(x,y,z))
				if not cell.is_traversable:
					continue
				# For each cell, iterate over its potential neighbours
				for y_offset in range(-1, 2):
					var neighbour_y = y + y_offset
					# Skip y coordinates outside the grid
					if neighbour_y < 0 or neighbour_y >= cell_dimensions.y:
						continue
					for x_offset in range(-1, 2):
						var neighbour_x = x + x_offset
						# Skip x coordinates outside the grid
						if neighbour_x < 0 or neighbour_x >= cell_dimensions.x:
							continue
						for z_offset in range(-1, 2):
							var neighbour_z = z + z_offset
							# Skip z coordinates outside the grid 
							if neighbour_z < 0 or neighbour_z >= cell_dimensions.z:
								continue
							var neighbour_indices = Vector3(neighbour_x, neighbour_y, neighbour_z)
							# Skip checking the original point
							if neighbour_indices == cell.indices:
								continue
							evaluate_neighbour(cell, grid[neighbour_indices.y][neighbour_indices.x][neighbour_indices.z], current_game_space)
				if is_debug and debug_draw_mode == DebugDrawModes.NEIGHBOURS:
					cell.set_debug_mesh(debug_meshes[cell.neighbours.size()])

# Test if a cell is a valid neighbour for our original_cell
func evaluate_neighbour(original_cell: NavMapCell, test_cell: NavMapCell, queryable_game_space: PhysicsDirectSpaceState):
	if test_cell.is_traversable:
		var is_valid_neighbour := true
		if check_neighbours_line_of_sight:
			var raycast_result = queryable_game_space.intersect_ray(original_cell.point_origin, test_cell.point_origin, [], world_collision_mask)
			if raycast_result.size() > 0:
				# Our neighbour is out of line of sight, exclude it
				is_valid_neighbour = false
		if is_valid_neighbour:
			original_cell.add_neighbour(test_cell.indices)

## NAVIGATION METHODS
# Just AABBCC detection atm, could maybe use an area instead?
func is_point_inside(world_position: Vector3) -> bool:
	return (world_position.x >= top_left_back.x and world_position.x < bottom_right_front.x) and (world_position.z >= top_left_back.z and world_position.z < bottom_right_front.z) and (world_position.y <= top_left_back.y and world_position.y > bottom_right_front.y)

func find_closest_nav_cell(world_position: Vector3):
	if is_point_inside(world_position):
		var cell_indices = get_cell_indices(world_position)
		var cell: NavMapCell = get_cell(cell_indices)
		if cell.is_traversable:
			return cell
		else:
			# Check all neighbours
			var some_valid_neighbour = find_any_traversable_neighbour(cell)
			if some_valid_neighbour:
				return some_valid_neighbour
			push_warning('cell is not traversible and has no valid neighours..')
			return null
	else:
		push_warning('find_closest_nav_cell(): world position is outside nav map')
		# Can we clamp the position to the edge of the nav map bounds and THEN do cell maths? 
		# Brain dead easy way might be to have the entities move_and_slide directly towards the centre of the nav area >_>
		return null

func find_any_traversable_neighbour(cell: NavMapCell) -> NavMapCell:
	for y_offset in range(-1, 2):
		var neighbour_y = cell.indices.y + y_offset
		# Skip y coordinates outside the grid
		if neighbour_y < 0 or neighbour_y >= cell_dimensions.y:
			continue
		for x_offset in range(-1, 2):
			var neighbour_x = cell.indices.x + x_offset
			# Skip x coordinates outside the grid
			if neighbour_x < 0 or neighbour_x >= cell_dimensions.x:
				continue
			for z_offset in range(-1, 2):
				var neighbour_z = cell.indices.z + z_offset
				# Skip z coordinates outside the grid 
				if neighbour_z < 0 or neighbour_z >= cell_dimensions.z:
					continue
				var neighbour_indices = Vector3(neighbour_x, neighbour_y, neighbour_z)
				# Skip checking the original point
				if neighbour_indices == cell.indices:
					continue
				
				var neighbour_cell: NavMapCell = get_cell(neighbour_indices)
				if neighbour_cell.is_traversable:
					return neighbour_cell
	return null

func calculate_path(from: Vector3, to: Vector3):
	var empty_path = []
	if not is_nav_mesh_ready:
		return empty_path
	if not is_point_inside(to):
		push_warning("Attempting to calculate path to destination outside nav map")
		return empty_path
	var start: NavMapCell = find_closest_nav_cell(from)
	var end: NavMapCell = find_closest_nav_cell(to)
	if not start or not end:
		return empty_path
	#https://en.wikipedia.org/wiki/A*_search_algorithm
	var open_set_queue: Array = []
	var open_set_occupancy_map: Dictionary = {}
	open_set_queue.append(SearchCell.new(start, 0))
	open_set_occupancy_map[start.indices] = true
	
	var came_from: Dictionary = {}
	
	# For node n, goal_score[n.indices] is the cost of the cheapest path from start to n currently known.
	var goal_score: Dictionary = {}
	goal_score[start.indices] = 0
	
	# For node n, fScore[n] := gScore[n] + h(n). fScore[n] represents our current best guess as to
	# how short a path from start to finish can be if it goes through n.
	var finish_score: Dictionary = {}
	finish_score[start.indices] = calculate_heuristic(start.point_origin, end.point_origin)
	
	var path_calculation_start_time = OS.get_unix_time()
	while open_set_queue.size() > 0:
		if OS.get_unix_time() > path_calculation_start_time + maximum_path_calculation_duration:
			push_warning("Airborne nav calculation exceeded max duration, aborting thread")
			return empty_path
		# Take our first item (this is a sorted array, so this is the lowest score node in the open set).
		var current: SearchCell = open_set_queue.pop_front()
		open_set_occupancy_map[current.cell.indices] = false
		if current.cell.indices == end.indices:
			return reconstruct_path(current, came_from)
		
		var added_to_open_set = false
		for neighbour_indices in current.cell.neighbours:
			var neighbour_cell = get_cell(neighbour_indices)
			# Currently we don't need distance as we aren't actually displacing any of the point_origin's (they're all cell centres)
#			var tentative_score = current.score + current.cell.point_origin.distance_to(neighbour_cell.point_origin) # distance from the current -> neighbour
			var tentative_score = current.score + 1 # one is the distance from the current -> neighbour, could be given a value in future
			if not goal_score.has(neighbour_indices) or tentative_score < goal_score[neighbour_indices]:
				# This path to neighbor is better than any previous one. Record it!
				came_from[neighbour_indices] = current
				goal_score[neighbour_indices] = tentative_score
				finish_score[neighbour_indices] = goal_score[neighbour_indices] + calculate_heuristic(neighbour_cell.point_origin, end.point_origin)
				if not open_set_occupancy_map.get(neighbour_indices):
					open_set_queue.append(SearchCell.new(neighbour_cell, finish_score[neighbour_indices]))
					open_set_occupancy_map[neighbour_indices] = true
					added_to_open_set = true
		if added_to_open_set:
			open_set_queue.sort_custom(ScoreSorter, "sort_by_ascending_score")
	 # Open set is empty but goal never reached, no path...
	return empty_path

func calculate_heuristic(point: Vector3, goal: Vector3) -> float:
	# Just linear distance (using world coords)
	return point.distance_to(goal)

func reconstruct_path(from: SearchCell, came_from_map: Dictionary) -> Array:
	var current = from
	var path = [current.cell.point_origin]
	while came_from_map.has(current.cell.indices):
		current = came_from_map[current.cell.indices]
		path.push_front(current.cell.point_origin)
	return path

## HELPER methods
func get_cell(indices: Vector3) -> NavMapCell:
	return grid[indices.y][indices.x][indices.z]

func get_cell_centre(indices: Vector3) -> Vector3:
	# should be positive x & z, negative y (from top_left_back)
	return top_left_back + (Vector3(indices.x, -indices.y, indices.z) * step_size) + cell_centre_offset

# Assumes the point is inside the nav mesh (i.e. is_point_inside is true)
func get_cell_indices(position: Vector3) -> Vector3:
	var local_from_origin = position - top_left_back
	var scaled_position = local_from_origin / step_size
	# Using top left as the origin means dark magic for the y coordinate >_>
	return Vector3(floor(scaled_position.x), abs(ceil(scaled_position.y)), floor(scaled_position.z))

## DEBUG drawing functions
func generate_debug_coloured_meshes():
	match debug_draw_mode:
		DebugDrawModes.NEIGHBOURS: # Neighbours
			var base_material: SpatialMaterial = preload("res://materials/debug_highlight_purple.tres")
			var default_mesh = debug_point_mesh.duplicate()
			default_mesh.surface_set_material(0, base_material)
			debug_meshes[0] = default_mesh
			# 26 is max possible number of neighbours
			for i in range(1,27):
				# Sample the gradient for a colour, create a material for each (corresponding to # of neighbours)
				var gradient_offset = float(i)/float(26)
				var coloured_material: SpatialMaterial = base_material.duplicate()
				coloured_material.albedo_color = debug_neighbours_gradient.interpolate(gradient_offset)
				var coloured_mesh = debug_point_mesh.duplicate()
				coloured_mesh.surface_set_material(0, coloured_material)
				debug_meshes[i] = coloured_mesh
				
		DebugDrawModes.OCCLUSION: # Occlusion
			var default_mesh = debug_point_mesh.duplicate()
			default_mesh.surface_set_material(0, preload("res://materials/debug_highlight_purple.tres"))
			debug_meshes[0] = default_mesh
			var highlight_mesh = debug_point_mesh.duplicate()
			highlight_mesh.surface_set_material(0, preload("res://materials/debug_highlight_orange.tres"))
			debug_meshes["HIGHLIGHT"] = highlight_mesh
			var anchor_mesh = debug_point_mesh.duplicate()
			anchor_mesh.surface_set_material(0, preload("res://materials/debug_highlight_blue.tres"))
			debug_meshes["ANCHOR"] = anchor_mesh

# Add mesh instances to each cell for debug rendering
func populate_debug_point_meshes():
	var debug_node = get_node("DEBUG")
	for y in range(len(grid)):
		for x in range(len(grid[y])):
			for z in range(len(grid[y][x])):
				var cell: NavMapCell = get_cell(Vector3(x,y,z))
				var mesh_instance = MeshInstance.new()
				mesh_instance.cast_shadow = false
				mesh_instance.mesh = debug_meshes[0]
				cell.debug_mesh_instance = mesh_instance
				debug_node.add_child(mesh_instance)
				mesh_instance.global_transform.origin = get_cell_centre(cell.indices)
				if debug_draw_mode == DebugDrawModes.OCCLUSION and (cell.indices == Vector3.ZERO or cell.indices == (cell_dimensions - Vector3(1,1,1))):
					cell.set_debug_mesh(debug_meshes['ANCHOR'])

func generate_debug_point_mesh():
	var base_mesh = CubeMesh.new()
	base_mesh.size = Vector3(point_geometry_collision_margin, point_geometry_collision_margin, point_geometry_collision_margin)
	debug_point_mesh = base_mesh

func _exit_tree():
	if generation_thread:
		print('wait for airborne navmap generation thread to terminate')
		generation_thread.wait_to_finish()
		print('airborne navmap generation thread cleaned up')
	for y in range(len(grid)):
		for x in range(len(grid[y])):
			for z in range(len(grid[y][x])):
				var cell = get_cell(Vector3(x,y,z))
				cell.clear_references()
				grid[y][x][z] = null
			grid[y][x] = null
		grid[y] = null
	grid.clear()
	debug_meshes.clear()