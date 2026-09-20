extends SceneTree
const Tactics=preload("res://tactics.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS: " if ok else "FAIL: ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.active=false
	var probe_cell: Vector2i=game._cell(Vector2(-5,-2))
	var temporary_wall:=Rect2(-5.2,-2.2,0.4,0.4)
	game.level.obstacles.append(temporary_wall)
	game._build_nav()
	check(game.nav.is_point_solid(probe_cell),"nav rebuild adds a newly placed wall")
	game.level.obstacles.erase(temporary_wall)
	game._build_nav()
	check(not game.nav.is_point_solid(probe_cell),"nav rebuild clears removed cover instead of retaining ghost walls")
	game.time=20.0
	var guard: Dictionary=game.guards[0]
	guard.pos=Vector2(-5,4)
	guard.last_seen=Vector2(6,0)
	guard.seen_at=20.0
	var dest: Vector2=Tactics.flank_destination(game,guard,guard.last_seen)
	check(dest.y>3.0 and dest.x>5.0,"flank targets the observed southeast escape approach")
	game.player_pos=Vector2(-12,-8)
	check(dest==Tactics.flank_destination(game,guard,guard.last_seen),"unseen player position does not affect flank target")
	Tactics.assign(game,guard,"flank",Vector2(4,-2))
	Tactics.tick(game,guard)
	check(guard.target==dest,"fresh reported contact replaces obsolete lateral target")
	guard.last_seen=Vector2(9,5)
	game.time=21.0
	guard.seen_at=21.0
	Tactics.tick(game,guard)
	check(guard.target.distance_to(game.EXITS[1])<dest.distance_to(game.EXITS[1]),"updated report advances intercept toward the exit")
	guard.pos=guard.target
	game.time=22.0
	guard.seen_at=22.0
	Tactics.tick(game,guard)
	check(guard.role=="pursue","arrival transitions to engagement rather than waiting")
	Tactics.assign(game,guard,"flank",dest)
	game.time=28.0
	Tactics.tick(game,guard)
	check(guard.role=="search","expired contact falls back to last-known search")
	game.guards[1].direct_seen_at=28.0
	game.power_on=true
	check(game._team_has_visual_contact(guard),"fresh teammate visual report prevents redundant lost-contact plan")
	game.power_on=false
	game.guards[1].pos=Vector2(-12,-8)
	check(not game._team_has_visual_contact(guard),"disconnected teammate does not provide contact knowledge")
	print("FLANK_VERIFICATION ",checks," checks, ",failures," failures")
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
