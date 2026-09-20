extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures+=1
func key(game,code: Key) -> void:
	var event:=InputEventKey.new()
	event.pressed=true
	event.physical_keycode=code
	game._unhandled_key_input(event)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://courtyard.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	check(game.tactical_assist and not game.replay.comparing and not game.active and game.intro.visible,"Play entry starts the new map with manual controls and an introduction")
	check(not game.replay.invulnerable,"Play entry uses ordinary health")
	key(game,KEY_ENTER)
	check(game.active and not game.intro.visible,"Enter starts manual play")
	game.mode="rules"
	var start: Vector2=game.player_pos
	Input.action_press("move_right")
	game._physics_process(1.0/60)
	Input.action_release("move_right")
	check(game.player_pos.x>start.x,"manual movement works on the new map")
	key(game,KEY_M)
	check(game.mode=="jev","M enables Jev on top of the shared AI")
	key(game,KEY_R)
	check(game.player_hp==100 and not game.replay.comparing and game.active,"R restores a playable mission")
	print("BUNDLE_ENTRY_FAILURES ",failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
