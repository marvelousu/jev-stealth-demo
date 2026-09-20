extends SceneTree

const SERVICE_URL: String = "https://relay-jev-demo.maro6052.workers.dev"
const TICK_DELTA: float = 1.0 / 60.0
const SAMPLE_EVERY: int = 12
const MAX_TICKS: int = 8000


func _initialize() -> void:
	call_deferred("run")


func point(value: Vector2) -> Array:
	return [value.x, value.y]


func guard_snapshot(guard: Dictionary) -> Dictionary:
	return {
		"id": guard.get("id", ""),
		"pos": point(guard.get("pos", Vector2.ZERO)),
		"target": point(guard.get("target", Vector2.ZERO)),
		"role": guard.get("role", ""),
		"face": point(guard.get("face", Vector2.ZERO)),
		"detect": guard.get("detect", 0.0),
		"seen_at": guard.get("seen_at", -100.0),
		"direct_seen_at": guard.get("direct_seen_at", -100.0),
	}


func frame_snapshot(game) -> Dictionary:
	var guards: Array = []
	for guard: Dictionary in game.guards:
		guards.append(guard_snapshot(guard))
	return {
		"time": game.time,
		"player": point(game.player_pos),
		"hp": game.player_hp,
		"has_case": game.has_case,
		"guards": guards,
		"choice": game.decision_name,
	}


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scenario: String = "rush" if args.is_empty() else str(args[0])
	var game = load("res://courtyard.tscn").instantiate()
	game.service_url = SERVICE_URL
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)

	var replay = game.replay
	replay.scenario = scenario
	replay.comparing = true
	replay.phase = 0
	replay.comparison_results.clear()
	replay.begin_phase(game)

	var frames: Dictionary = {"rules": [], "jev": []}
	var tick: int = 0
	while replay.comparing and tick < MAX_TICKS:
		game._physics_process(TICK_DELTA)
		await physics_frame
		if tick % SAMPLE_EVERY == 0 and replay.comparing:
			frames[game.mode].append(frame_snapshot(game))
		tick += 1

	var output_path: String = "res://qa/video/guard-v10-%s.json" % scenario
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "passes": replay.comparison_results}, "\t"))
	file.close()
	print("GUARD_V10_PROBE_DONE ", output_path, " ticks=", tick)
	game.queue_free()
	await process_frame
	quit()
