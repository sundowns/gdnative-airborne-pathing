WIP GDNative module for airborne pathing, transcribing a GDScript module from an upcoming FPS game. This module generates airborne nav meshes, avoiding geometry and providing A\* path finding for agents throughout the open space.

https://godot-rust.github.io/book/getting-started/hello-world.html

You should now be able to build the dynamic library with a HelloWorld script class in it. However, we also need to tell Godot about it. To do this, build the library with cargo build.

After building the library with cargo build, the resulting library should be in the target/debug/ folder. Copy it (or create a symbolic link to it) somewhere inside the Godot project directory.

To tell Godot about the HelloWorld class, a GDNativeLibrary resource has to be created. This can be done in the "Inspector" panel in the Godot editor by clicking the "new resource" button in the top left.

With the GDNativeLibrary resource created, the path to the generated binary can be set in the editor. After specifying the path, save the GDNativeLibrary resource into a resource file by clicking the "tool" button in the Inspector panel in the top right.

Now, the HelloWorld class can be added to any node by clicking the "add script" button. In the popup, select "NativeScript" as the language, and set the class name to HelloWorld. Then, select the NativeScript resource in the Inspector, click the library field and point to the GDNativeLibrary resource that you created earlier.
