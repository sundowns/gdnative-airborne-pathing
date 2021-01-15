use gdnative::prelude::*;

/// The HelloWorld "class"
#[derive(NativeClass)]
#[inherit(Node)]
pub struct AirborneNavigationManager;

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

// Function that registers all exposed classes to Godot
fn init(handle: InitHandle) {
    // Register the new `HelloWorld` type we just declared.
    handle.add_class::<AirborneNavigationManager>();
}

// Macro that creates the entry-points of the dynamic library.
godot_init!(init);
