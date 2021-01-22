use gdnative::prelude::*;

/// The HelloWorld "class"
#[derive(NativeClass)]
#[inherit(Node)]
#[register_with(register_properties)]
pub struct AirborneNavigationManager {
    // Distance between each nav point along each axes.
    step_size: f32,
    // 1/2 Width of the box shape to detect occlusion with.
    point_geometry_collision_margin: f32,
    // Whether or not we should look for LOS between neighbours to determine connectivity.
    check_neighbours_line_of_sight: bool,
    // Collision layer mask to determine what is invalid geometry for a point to be colliding with.
    world_collision_mask: i32,
    // Top left back point, derived directly from the global_transform.origin of a child spatial node called 'TopLeftBack'
    top_left_back: Vector3,
    // Bottom right front point, derived directly from the global_transform.origin of a child spatial node called 'BottomRightFront'
    bottom_right_front: Vector3,
    // Float dimensions of the 3D nav grid in game-space
    grid_dimensions: Vector3,
    // Integer dimensions (cell counts)
    cell_dimensions: Vector3,
    // Offset from a point to the centre of its cell (points refer to top/left/back point in a cell, so point + offset -> middle of cell)
    cell_centre_offset: Vector3,
}

// Only __one__ `impl` block can have the `#[methods]` attribute, which
#[methods]
impl AirborneNavigationManager {
    /// The "constructor" of the class.
    fn new(_owner: &Node) -> Self {
        AirborneNavigationManager
    }

    // To make a method known to Godot, use the #[export] attribute.
    // In Godot, script "classes" do not actually inherit the parent class.
    // Instead, they are "attached" to the parent object, called the "owner".
    //
    // In order to enable access to the owner, it is passed as the second
    // argument to every single exposed method. As a result, all exposed
    // methods MUST have `owner: &BaseClass` as their second arguments,
    // before all other arguments in the signature.
    #[export]
    fn _ready(&self, _owner: &Node) {
        // The `godot_print!` macro works like `println!` but prints to the Godot-editor
        // output tab as well.
        godot_print!("Hello, world!");
    }
}

fn register_properties(builder: &ClassBuilder<AirborneNavigationManager>) {}

pub struct NavMapCell<'a> {
    pub is_traversable: bool,
    pub is_occluded: bool,
    pub indices: Vector3,
    pub point_origin: Vector3,
    pub neighbours: Vec<&'a NavMapCell<'a>>,
    // debug_mesh_instance: MeshInstance,
}

impl<'a> NavMapCell<'a> {
    fn new(_indices: Vector3, _point_origin: Vector3) -> Self {
        NavMapCell {
            is_traversable: true,
            is_occluded: false,
            indices: _indices,
            point_origin: _point_origin,
            neighbours: vec![],
        }
    }
    fn add_neighbour(&mut self, neighbour: &'a NavMapCell) {
        &self.neighbours.push(neighbour);
    }
}

pub struct SearchCell<'a> {
    pub cell: &'a NavMapCell<'a>,
    pub score: f32,
}

impl<'a> SearchCell<'a> {
    fn new(_cell: &'a NavMapCell, _score: f32) -> SearchCell<'a> {
        SearchCell {
            cell: _cell,
            score: _score,
        }
    }
}

// var cell: NavMapCell
// var score: float
// func _init(_cell: NavMapCell, _score: float):
// cell = _cell
// score = _score

// var is_traversable: bool
// var is_occluded: bool
// var indices: Vector3
// var debug_mesh_instance: MeshInstance
// var point_origin: Vector3
// var neighbours: Array
// func _init(_indices: Vector3, _point_origin: Vector3):
//     self.is_traversable = true
//     self.is_occluded = false
//     self.indices = _indices
//     self.point_origin = _point_origin
//     self.neighbours = []
// func set_as_occluded():
//     self.is_occluded = true
// func set_debug_mesh(mesh: Mesh):
//     if self.debug_mesh_instance:
//         self.debug_mesh_instance.mesh = mesh
// func set_not_traversable():
//     self.is_traversable = false
//     if self.debug_mesh_instance:
//         self.debug_mesh_instance.queue_free()
//         self.debug_mesh_instance = null
// func add_neighbour(neighbour_indices: Vector3):
//     neighbours.append(neighbour_indices)
// func clear_references():
//     neighbours.clear()
//     if debug_mesh_instance:
//         debug_mesh_instance.mesh = null
//         debug_mesh_instance.free()

// Function that registers all exposed classes to Godot
fn init(handle: InitHandle) {
    // Register the new `HelloWorld` type we just declared.
    handle.add_class::<AirborneNavigationManager>();
}

// Macro that creates the entry-points of the dynamic library.
godot_init!(init);
