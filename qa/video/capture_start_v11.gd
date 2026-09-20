extends SceneTree
## Capture the actual initial scene without advancing the simulation.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://courtyard.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.tactical_view.set_process(false)
	game.tactical_view.hide()
	game.replay.comparing = false
	game._reset()
	game.active = false
	game.intro.hide()
	game.result_panel.hide()
	for guard: Dictionary in game.guards:
		guard.node.rotation.y = atan2(-guard.face.x, -guard.face.y)
	game._draw_senses(false)
	game._update_plan_lines()
	game._update_ui()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("res://qa/video/guard-v11-start.jpg", 0.98)
	var meta := {"time": game.time, "player": [game.player_pos.x, game.player_pos.y], "guards": []}
	for guard: Dictionary in game.guards:
		meta.guards.append({"id": guard.id, "pos": [guard.pos.x, guard.pos.y], "face": [guard.face.x, guard.face.y]})
	var file := FileAccess.open("res://qa/video/guard-v11-start.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(meta, "\t"))
	print("V11_INITIAL_STILL ", JSON.stringify(meta))
	quit()
