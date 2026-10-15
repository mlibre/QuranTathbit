extends SceneTree

## Rasterize the app icon into the sizes Android's launcher wants.
## Run: godot --headless --path . --script tools/make_icons.gd

const OUT := "res://assets/icons/"

func _init() -> void:
        var texture: Texture2D = load("res://assets/icons/icon.svg")
        if texture == null:
                push_error("make_icons: icon.svg did not load")
                quit(1)
                return
        var base: Image = texture.get_image()
        for pair in [["icon_192.png", 192], ["icon_432.png", 432]]:
                var size: int = pair[1]
                var img: Image = base.duplicate()
                img.resize(size, size, Image.INTERPOLATE_LANCZOS)
                var err := img.save_png(OUT + str(pair[0]))
                print("wrote ", pair[0], " (", size, "px): ", error_string(err))
        # adaptive-background: the same deep green the icon edges use
        var bg := Image.create_empty(432, 432, false, Image.FORMAT_RGB8)
        bg.fill(Color("#14513D"))
        bg.save_png(OUT + "icon_bg.png")
        print("wrote icon_bg.png")
        quit(0)
