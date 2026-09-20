extends SceneTree

const FOLDER := "res://qa/video/guard-v10-release"
const SERVICE_URL := "https://relay-jev-demo.maro6052.workers.dev"
const SCENARIO := "loop"
const TICK_DELTA := 1.0 / 60.0
const SAMPLE_EVERY := 4
const MAX_TICKS := 6000


func _initialize() -> void:
	call_deferred("run")


func point(value: Vector2) -> Array:
	return [value.x, value.y]


func _guard_sample(guard: Dictionary) -> Dictionary:
	return {
		"id": guard.id,
		"pos": point(guard.pos),
		"target": point(guard.target),
		"role": guard.role,
		"hp": guard.hp,
		"fire": guard.fire,
		"face": point(guard.face),
		"detect": guard.detect,
		"seen_at": guard.seen_at,
		"direct_seen_at": guard.get("direct_seen_at", -100.0),
	}


func run() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var game = load("res://courtyard.tscn").instantiate()
	game.service_url = SERVICE_URL
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.tactical_view.set_process(false)
	game.tactical_view.hide()

	var replay = game.replay
	replay.scenario = SCENARIO
	replay.comparing = true
	replay.phase = 0
	replay.comparison_results.clear()
	replay.begin_phase(game)

	var counts: Dictionary = {"rules": 0, "jev": 0}
	var frames: Dictionary = {"rules": [], "jev": []}
	var obstacles: Array = []
	for obstacle: Rect2 in game.level.obstacles:
		obstacles.append([obstacle.position.x, obstacle.position.y, obstacle.size.x, obstacle.size.y])
	for mode in counts:
		DirAccess.make_dir_recursive_absolute(FOLDER + "/" + mode)

	var tick: int = 0
	while replay.comparing and tick < MAX_TICKS:
		game._physics_process(TICK_DELTA)
		await physics_frame
		if tick % SAMPLE_EVERY == 0 and replay.comparing:
			game._update_ui()
			if game.finished: game.result_panel.hide()
			var sample: Dictionary = {
				"time": game.time,
				"player": point(game.player_pos),
				"player_hp": game.player_hp,
				"guards": [],
				"devices": [],
				"smokes": [],
				"choice": game.decision_name,
				"source": game.decision_source,
				"pending": game.pending,
				"has_case": game.has_case,
				"stage": game.replay.objective_stage,
				"interaction": game.interaction_progress,
			}
			for guard: Dictionary in game.guards:
				sample.guards.append(_guard_sample(guard))
			for device: Dictionary in game.devices:
				sample.devices.append(point(device.pos))
			for smoke: Dictionary in game.smokes:
				sample.smokes.append(point(smoke.pos))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(FOLDER + "/%s/%05d.jpg" % [game.mode, counts[game.mode]], 0.96)
			frames[game.mode].append(sample)
			counts[game.mode] += 1
		tick += 1

	var file := FileAccess.open(FOLDER + "/recording.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "passes": replay.comparison_results, "obstacles": obstacles, "counts": counts}, "\t"))
	file.close()
	print("GUARD_V10_CAPTURE_DONE ", JSON.stringify(counts))
	game.queue_free()
	await process_frame
	quit()
