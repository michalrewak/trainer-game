class_name Screenshot
extends RefCounted
## Zrzut ekranu po narysowaniu klatki (testy wizualne: --screenshots=KATALOG).


static func capture(node: Node, path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := node.get_viewport().get_texture().get_image()
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := image.save_png(path)
	print("Zrzut ekranu: %s (%s)" % [path, error_string(err)])
