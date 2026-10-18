extends SceneTree

## Rasterize the app's icon into every size a launcher or a browser asks for.
## Run: godot --headless --path . --import
## then godot --headless --path . --script tools/make_icons.gd
##
## The art lives in three SVGs: icon.svg (the whole face, green to its
## edges), icon_fg.svg (the art alone on transparency, held inside the
## circle no launcher crops, for Android's adaptive foreground) and
## icon_maskable.svg (the whole face again, art pulled in to the safe circle
## a home screen's mask respects, for the PWA). Each SVG declares its own
## raster size, so the importer bakes them at full sharpness and this only
## writes the PNGs the presets and the web build point at.

const OUT := "res://assets/icons/"

func _init() -> void:
        var ok := true
        # The launcher's own face at the size Android's manifest names, and
        # the fallback every legacy launcher shows.
        ok = ok and _rasterize("res://assets/icons/icon.svg", 192, "icon_192.png")
        # Android's adaptive icon: the art on transparency, and beneath it
        # the same deep green the icon's own edges wear.
        ok = ok and _rasterize("res://assets/icons/icon_fg.svg", 432, "icon_432.png")
        var bg := Image.create_empty(432, 432, false, Image.FORMAT_RGB8)
        bg.fill(Color("#14513D"))
        ok = ok and _write(bg, "icon_bg.png")
        # The PWA's maskable face: whole, green to every edge, the art
        # inside the safe circle.
        ok = ok and _rasterize("res://assets/icons/icon_maskable.svg", 512, "icon_maskable_512.png")
        quit(0 if ok else 1)


func _rasterize(svg_path: String, size: int, out_name: String) -> bool:
        var texture: Texture2D = load(svg_path)
        if texture == null:
                push_error("make_icons: %s did not load" % svg_path)
                return false
        var img: Image = texture.get_image()
        if img == null:
                push_error("make_icons: %s gave no image" % svg_path)
                return false
        if img.get_width() != size or img.get_height() != size:
                img.resize(size, size, Image.INTERPOLATE_LANCZOS)
        return _write(img, out_name)


func _write(img: Image, out_name: String) -> bool:
        var err := img.save_png(OUT + out_name)
        print("wrote ", out_name, " (", img.get_width(), "px): ", error_string(err))
        return err == OK
