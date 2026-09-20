extends SceneTree
var failures: Array=[]
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error(label)
func key(game,k: int) -> void:
	var e:=InputEventKey.new();e.physical_keycode=k;e.pressed=true;game._unhandled_key_input(e)
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	game.service_url="http://127.0.0.1:1";root.add_child(game);await process_frame;game.set_physics_process(false)
	key(game,KEY_F1)
	check(game.explanation.is_open() and game.paused,"F1 opens paused explanation")
	check(game.explanation.choice_label.text.contains("未記録"),"no fabricated decision before data")
	key(game,KEY_M);check(game.mode=="jev","modal blocks mode switch")
	key(game,KEY_F1);check(not game.paused,"close restores running state")
	game.paused=true;key(game,KEY_F1);key(game,KEY_ESCAPE);check(game.paused,"close preserves prior pause")
	game.paused=false;game.mode="rules";game.active=true;game.intro.hide()
	game._request_decision(game.guards[0],"noise",Vector2(-7,1),["inspect","paired_inspection","hold_position"])
	check(game.trace.size()==1,"actual rule decision recorded")
	var entry: Dictionary=game.trace.back()
	check(entry.observer=="A" and entry.candidates.size()==3,"observer and offered choices captured")
	check(entry.assignments.size()==3,"actual assignment snapshot recorded")
	var saved: Vector2=entry.assignments[0].target
	game.guards[0].target=Vector2(1,2)
	check(entry.assignments[0].target==saved,"later guard mutation cannot rewrite assignment history")
	key(game,KEY_F1)
	check(game.explanation.choice_label.text.contains("ルール") and game.explanation.assignments_label.text.contains("A"),"actual source and assignment rendered")
	key(game,KEY_F1)
	game.start_guided_comparison()
	check(game.guided_comparison and game.replay.comparing and game.replay.variant==0,"guided comparison starts standard condition")
	for i in range(1400):
		game._physics_process(1.0/60)
		if game.paused:break
	check(game.explanation.is_open() and game.trace.size()==3,"guided rule phase stops on third adopted decision")
	var held_time: float=game.time
	game._physics_process(1)
	check(game.time==held_time,"guided explanation stops simulation")
	game.explanation.close(game);game._physics_process(1.0/60)
	check(game.time>held_time,"closing resumes movement")
	key(game,KEY_R)
	check(not game.guided_comparison and not game.replay.comparing and not game.paused,"R leaves guided observation for ordinary mission")
	# Exercise long/fallback text and actual Control geometry through rendered layout.
	entry.source="代替ルール";game.explanation.show_panel(game,entry)
	await process_frame;await process_frame
	check(game.explanation.choice_label.text.contains("代替"),"fallback never labeled Jev")
	check(game.explanation.panel.size.y<=705 and game.explanation.panel.size.x<=1305,"panel fits intended viewport")
	game.explanation.close(game)
	print("EXPLANATION_TEST ",checks," checks ",failures.size()," failures ",failures)
	game.queue_free();await process_frame;await create_timer(0.3).timeout;quit(0 if failures.is_empty() else 1)
