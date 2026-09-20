extends SceneTree

const Tactics = preload("res://tactics.gd")

var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: " + label)
		quit(1)
		assert(condition, label)
	checks += 1
	print("PASS: ", label)

func reset_to_rules(game) -> void:
	game._reset()
	game.mode = "rules"
	await process_frame

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.mode = "rules"
	var points := [Vector2(-11,8), game.CASE_POS, game.POWER_POS, game.EXITS[0], game.EXITS[1]]
	for point: Vector2 in points:
		check(not game._blocked(point,0.42), "critical point is walkable " + str(point))
		check(not game.nav.get_point_path(game._cell(points[0]),game._cell(point)).is_empty(), "critical point is reachable " + str(point))
	# Follow the actual controller along the entire nav path, including the doorway.
	var route: PackedVector2Array = game.nav.get_point_path(game._cell(points[0]),game._cell(game.CASE_POS))
	var pos: Vector2 = points[0]
	for waypoint in route:
		for step in range(120):
			if pos.distance_to(waypoint)<0.12: break
			pos=game._move(pos,(waypoint-pos).limit_length(4.6/60))
	check(pos.distance_to(game.CASE_POS)<0.3,"controller traverses case route without door snag")
	check(not game._clear_line(Vector2(0,-2),Vector2(0,1)),"cover blocks line of sight")
	check(game._clear_line(Vector2(-10,5),Vector2(-10,7)),"open space permits line of sight")
	game.smokes.append({"pos":Vector2(-10,6)})
	check(not game._clear_line(Vector2(-10,5),Vector2(-10,7)),"smoke blocks sight")
	game.smokes.clear()
	game.power_on=false
	check(not game._can_radio(game.guards[0],game.guards[2]),"power loss separates distant knowledge")
	game.power_on=true
	check(game._can_radio(game.guards[0],game.guards[2]),"powered relay shares reports")
	game.active=true
	for guard in game.guards: guard.face=Vector2.UP
	game.player_pos=game.CASE_POS
	Input.action_press("interact")
	for step in range(11): game._physics_process(0.1)
	check(not game.has_case,"case pickup does not complete before 1.2 seconds")
	game._physics_process(0.1)
	Input.action_release("interact")
	check(game.has_case,"case can be collected by holding mapped interact")
	check(not game.guards[0].missing_known,"unseen pickup does not inform guards")
	game._apply_decision("flank_and_cover",game.guards[2],Vector2(8,-3))
	var roles: Array=[]
	for guard in game.guards: roles.append(guard.role)
	check("pursue" in roles and "flank" in roles and "sentry" in roles,"combat preserves objective sentry while pursuing and flanking")

	await reset_to_rules(game)
	var sweep_observer: Dictionary=game.guards[0]
	game._apply_decision("sweep_last_known",sweep_observer,Vector2(7,-2))
	var sweep_sentry_count := 0
	var all_guards_live := true
	var all_guards_communicating := true
	for guard: Dictionary in game.guards:
		if guard.hp<=0: all_guards_live=false
		if not game._can_radio(sweep_observer,guard): all_guards_communicating=false
		if guard.role=="sentry": sweep_sentry_count+=1
	check(game.guards.size()==3 and all_guards_live and all_guards_communicating and sweep_sentry_count>=1,"sweep keeps a sentry with three live communicating guards")

	await reset_to_rules(game)
	var paired_observer: Dictionary=game.guards[0]
	var paired_location := Vector2(4,1)
	game._apply_decision("paired_inspection",paired_observer,paired_location)
	var paired_buddy: Dictionary={}
	var paired_has_sentry := false
	for guard: Dictionary in game.guards:
		if guard.role=="support": paired_buddy=guard
		if guard.role=="sentry": paired_has_sentry=true
	check(paired_observer.role=="wait_cover" and not paired_buddy.is_empty() and paired_buddy.role=="support" and paired_has_sentry,"paired inspection assigns wait-cover observer, support buddy, and sentry")
	if not paired_buddy.is_empty():
		if paired_buddy.pos.distance_to(paired_buddy.target)<=1.0:
			paired_buddy.pos=paired_buddy.target+Vector2(2,0)
		Tactics.tick(game,paired_observer)
		check(paired_observer.role=="wait_cover","wait-cover holds until support reaches target")
		paired_buddy.pos=paired_buddy.target
		Tactics.tick(game,paired_observer)
		check(paired_observer.role=="investigate","wait-cover investigates after support reaches target")

	await reset_to_rules(game)
	var dead_buddy_observer: Dictionary=game.guards[0]
	game._apply_decision("paired_inspection",dead_buddy_observer,paired_location)
	var dead_buddy: Dictionary={}
	for guard: Dictionary in game.guards:
		if guard.role=="support": dead_buddy=guard
	if not dead_buddy.is_empty():
		dead_buddy.hp=0
		Tactics.tick(game,dead_buddy_observer)
		check(dead_buddy_observer.role=="watch","wait-cover observer watches when support buddy dies")

	await reset_to_rules(game)
	var observation_observer: Dictionary=game.guards[0]
	var hidden_sentinel := Vector2(12345.0,67890.0)
	var known_event_point := Vector2(-10,5)
	game.player_pos=hidden_sentinel
	Tactics.observe(game,observation_observer,"gunfire",known_event_point,"Known gunfire event")
	var observation_text := JSON.stringify(Tactics.observations(game,observation_observer,"noise",known_event_point))
	check("Known gunfire event" in observation_text and "west courtyard" in observation_text and not ("12345" in observation_text or "67890" in observation_text),"observations expose known events and zones without hidden player position")

	await reset_to_rules(game)
	var age_observer: Dictionary=game.guards[0]
	Tactics.observe(game,age_observer,"noise",Vector2(-10,5),"First chronological fact")
	game.time=2.0
	Tactics.observe(game,age_observer,"gunfire",Vector2(-9,5),"Second chronological fact")
	game.time=5.0
	var aged_text := JSON.stringify(Tactics.observations(game,age_observer,"report",Vector2(-8,5)))
	var first_age_index: int=aged_text.find("5s ago: First chronological fact")
	var second_age_index: int=aged_text.find("3s ago: Second chronological fact")
	check(first_age_index>=0 and second_age_index>first_age_index,"observation fact ages advance chronologically")

	await reset_to_rules(game)
	var counter_observer: Dictionary=game.guards[0]
	var gunfire_point := Vector2(-10,5)
	var noise_point := Vector2(8,-3)
	game.time=10.0
	Tactics.observe(game,counter_observer,"gunfire",gunfire_point,"Observed distant gunfire")
	game.player_pos=Vector2(11111.0,22222.0)
	Tactics.apply(game,"counter_watch",counter_observer,noise_point)
	var first_ambush_target := Vector2.INF
	var first_watch := false
	var first_sentry := false
	for guard: Dictionary in game.guards:
		if guard==counter_observer and guard.role=="watch": first_watch=true
		if guard.role=="ambush": first_ambush_target=guard.target
		if guard.role=="sentry": first_sentry=true
	check(first_watch and first_ambush_target!=Vector2.INF and first_sentry,"counter-watch creates watch, ambush, and sentry roles")
	var exit_route: Vector2=game.EXITS[0]-Vector2(0,2)
	var exit_approach: Vector2=exit_route-Vector2(0,3)
	check(first_ambush_target.distance_to(exit_route)<4.0 and not game._blocked(first_ambush_target,0.45) and game._clear_line(first_ambush_target,exit_approach,false),"counter-watch ambush target covers the relevant exit route")
	game.player_pos=Vector2(-33333.0,-44444.0)
	Tactics.apply(game,"counter_watch",counter_observer,noise_point)
	var second_ambush_target := Vector2.INF
	for guard: Dictionary in game.guards:
		if guard.role=="ambush": second_ambush_target=guard.target
	check(second_ambush_target==first_ambush_target,"counter-watch target is unchanged by hidden player position")

	await reset_to_rules(game)
	var isolated_observer: Dictionary=game.guards[0]
	var isolated_remote_one: Dictionary=game.guards[1]
	var isolated_remote_two: Dictionary=game.guards[2]
	game.power_on=false
	var remote_one_role: String=isolated_remote_one.role
	var remote_two_role: String=isolated_remote_two.role
	check(not game._can_radio(isolated_observer,isolated_remote_one) and not game._can_radio(isolated_observer,isolated_remote_two),"power loss isolates remote guards")
	Tactics.apply(game,"flank_and_cover",isolated_observer,Vector2(8,-3))
	check(isolated_remote_one.role==remote_one_role and isolated_remote_two.role==remote_two_role,"isolated guards keep roles when observer applies a plan")

	await reset_to_rules(game)
	game.player_pos=game.CASE_POS
	game.active=true
	Input.action_press("interact")
	for step in range(12): game._physics_process(0.1)
	Input.action_release("interact")
	check(game.has_case,"mission completion scenario collects the case after holding interact")
	game.pending=true
	var old_revision: int=game.revision
	game._request_decision(game.guards[0],"contact",Vector2.ZERO,["flank_and_cover"])
	check(game.revision>old_revision,"new contact invalidates pending old choice")
	game.pending=false
	for guard in game.guards: guard.hp=0
	game.player_pos=game.EXITS[0]
	Input.action_press("interact")
	for step in range(24): game._physics_process(0.1)
	check(not game.finished,"carried case plus exit does not complete before 2.5 seconds")
	game._physics_process(0.1)
	Input.action_release("interact")
	check(game.finished and game.success,"carried case plus exit completes mission after holding interact")
	await reset_to_rules(game)
	check(not game.finished and not game.has_case and game.player_hp==100,"retry restores mission state")
	var begin: Vector2=game.player_pos
	var press:=InputEventKey.new()
	press.physical_keycode=KEY_D
	press.keycode=KEY_D
	press.pressed=true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	game.active=true
	game._physics_process(0.1)
	var release: InputEventKey=press.duplicate()
	release.pressed=false
	Input.parse_input_event(release)
	check(game.player_pos.x>begin.x,"WASD physical input drives the controller")
	print("GAME_VERIFICATION ",checks," checks passed")
	await create_timer(0.6).timeout
	game.queue_free()
	await process_frame
	quit(0)
