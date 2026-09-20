extends SceneTree
const Tactics=preload("res://tactics.gd")
const Mission=preload("res://mission.gd")
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS: " if ok else "FAIL: ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://courtyard.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.replay.comparing=false
	game.active=false
	game._reset()
	game.time=20
	var a: Dictionary=game.guards[0]
	var b: Dictionary=game.guards[1]
	var c: Dictionary=game.guards[2]
	Tactics.observe(game,a,"gunfire",Vector2(9,3),"Heard gunfire east")
	check(game.sight_range(a,true)==8.0,"heard gunfire raises alert even against crouching")
	Tactics.assign(game,b,"ambush",Vector2(9,4))
	b.watch_point=Vector2(9,0)
	Tactics.assign(game,c,"sentry",Vector2(10,-2))
	Tactics.apply(game,"hold_position",a,Vector2(-10,0))
	check(b.role=="ambush" and c.role=="sentry","holding a post preserves teammates' valid assignments")
	a.current_sound=Vector2(-10,0)
	Tactics.observe(game,a,"empty",a.current_sound,"Sound inspected empty")
	check(Tactics.baseline(game,a,"noise",["inspect","paired_inspection","counter_watch","hold_position"])=="counter_watch","ordinary AI already combines an empty check with prior gunfire elsewhere")
	check(Tactics.guard_speed("support")==Tactics.guard_speed("pursue"),"support moves with the same urgency as pursuit")
	a.last_seen=Vector2(-6,4);a.seen_at=19.9
	game._report_contact(a)
	check(b.seen_at==19.9,"radio preserves the actual sighting timestamp")
	game._reset();game.time=20;game.mode="jev";game.service_url="http://127.0.0.1:1"
	a=game.guards[0]
	game._request_decision(a,"contact",Vector2(-6,4),["flank_and_cover"])
	check(game.pending and game.trace.size()==1 and game.trace[0].source=="rules","Jev starts only after an immediate ordinary-AI response")
	var roles: Array=[]
	for g: Dictionary in game.guards: roles.append(g.role)
	check("pursue" in roles and "flank" in roles and "sentry" in roles,"ordinary AI immediately divides pursuit, interception and guarding")
	var revision: int=game.revision
	game._request_decision(a,"noise",Vector2(-10,0),["inspect"])
	check(game.revision==revision,"a queued weak sound does not invalidate a pending contact response")
	await create_timer(0.3).timeout
	var after: Array=[]
	for g: Dictionary in game.guards: after.append(g.role)
	check(after==roles,"failed Jev request preserves the active ordinary-AI plan")
	game.replay.comparing=true;game.replay.invulnerable=false;game.player_hp=100
	Mission.hurt(game,34,"A");Mission.hurt(game,34,"B");Mission.hurt(game,34,"C")
	check(game.player_hp==0,"new comparison has ordinary lethal damage")
	print("GUARD_V10_VERIFICATION ",checks," checks, ",failures," failures")
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
