extends SceneTree

const Mission=preload("res://mission.gd")
const STEP := 0.1
var failures:=0
var checks:=0

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS: " if ok else "FAIL: ",label)

func tick(game,count: int) -> void:
	for _i in range(count): game._physics_process(STEP)

func kill_guards(game) -> void:
	for guard: Dictionary in game.guards: guard.hp=0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game=load("res://courtyard.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)

	# F6 samples route, discrete actions, and E hold without recording mission state.
	game.replay.comparison_results=[{"success":false},{"success":true}]
	game.replay.toggle_record(game)
	kill_guards(game)
	check(game.replay.comparison_results.is_empty(),"F6 clears stale F8 comparison results")
	game.aim_pos=Vector2(-3,5)
	game._throw_noise(false)
	Input.action_press("move_right")
	tick(game,2)
	Input.action_release("move_right")
	var moved: Vector2=game.player_pos
	game.player_pos=game.CASE_POS+Vector2(0,0.7)
	game.player.position=game._v3(game.player_pos)
	Input.action_press("interact")
	tick(game,14)
	Input.action_release("interact")
	game.replay.toggle_record(game)
	check(game.replay.samples.size()>2 and moved.x>-11,"F6 records movement samples")
	check(game.replay.actions.any(func(action): return action.kind=="noise_single"),"F6 records a discrete action")
	check(game.replay.samples.any(func(sample): return bool(sample.get("interact",false))),"F6 records held E samples")
	check(game.has_case,"recorded E hold completes the real pickup")

	# F7 starts fresh and earns objectives through its held E samples rather than
	# copying has_case or HP from the recording.
	game.replay.play_recording(game)
	kill_guards(game)
	check(game.replay.playing and not game.has_case and game.player_hp==100,"F7 starts a fresh ordinary-health mission")
	tick(game,3)
	check(game.player_pos.x>-11 and game.noise_charges<3,"F7 applies recorded position and action")
	tick(game,20)
	check(game.has_case,"F7 replays held E to earn the case instead of copying it")
	Input.action_press("interact")
	game.replay.stop()
	check(not Input.is_action_pressed("crouch") and not Input.is_action_pressed("interact"),"stop releases synthetic crouch and E input")

	# Replay remains subject to ordinary lethal damage; the Courtyard node releases
	# synthetic input when the result panel is reached.
	game._reset()
	game.replay.playing=true
	game.replay.invulnerable=false
	game.replay.allows_objective_interactions=true
	Mission.hurt(game,34,"A")
	Mission.hurt(game,34,"B")
	Mission.hurt(game,34,"C")
	Mission.tick(game,STEP)
	check(game.player_hp==0 and game.finished,"F7 mode keeps ordinary lethal damage and failure")
	game._physics_process(STEP)
	check(not game.replay.playing and not Input.is_action_pressed("interact"),"lethal replay cleanup releases stale input")

	# Courtyard's comparison ending reports the real, per-mode mission outcomes.
	game._reset()
	game.replay.comparison_results=[
		{"success":false,"has_case":false,"hp":0,"duration":8.5},
		{"success":true,"has_case":true,"hp":66,"duration":15.0},
	]
	game.replay.end_observation(game,"検証用の比較結果")
	check(game.result_label.text.contains("通常AI：任務失敗") and game.result_label.text.contains("通常AI＋Jev：離脱成功") and game.result_label.text.contains("耐久66") and game.result_label.text.contains("ケース回収"),"Courtyard end screen reports per-mode outcome, case, HP, and time")
	game.replay.start_comparison(game)
	check(game.replay.comparing and not game.replay.invulnerable and game.active,"F8 comparison still starts with ordinary durability")
	game.replay.stop()

	Input.action_release("move_right")
	Input.action_release("interact")
	game.queue_free()
	await process_frame
	print("COURTYARD_REPLAY_VERIFICATION ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
