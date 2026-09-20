extends RefCounted
## Shared execution and observations: neither mode receives hidden player state.

class PlanContext extends RefCounted:
	var source
	var guards: Array=[]
	var nav: AStarGrid2D
	var time: float
	var CASE_POS: Vector2
	var EXITS: Array
	var last_plan: String=""
	func _init(game) -> void:
		source=game;guards=game.guards.duplicate(true);nav=game.nav;time=game.time
		CASE_POS=game.CASE_POS;EXITS=game.EXITS.duplicate()
	func _can_radio(a: Dictionary,b: Dictionary) -> bool: return source._can_radio(a,b)
	func _cell(p: Vector2) -> Vector2i: return source._cell(p)
	func _nearest_open(c: Vector2i) -> Vector2i: return source._nearest_open(c)
	func _blocked(p: Vector2,r: float) -> bool: return source._blocked(p,r)
	func _clear_line(a: Vector2,b: Vector2,smoke: bool=true) -> bool: return source._clear_line(a,b,smoke)
	func _log(_message: String) -> void: pass
	func plan_markers_refresh() -> void: pass

static func guard_speed(role: String) -> float:
	return 3.8 if role in ["pursue","flank","ambush","search","support","block","wait_cover","investigate"] else 1.9

static func forecast(game, observer: Dictionary, location: Vector2, candidates: Array) -> Array:
	var forecasts: Array=[]
	for candidate: String in candidates:
		var copy:=PlanContext.new(game)
		var copy_observer: Dictionary={}
		for member: Dictionary in copy.guards:
			if member.id==observer.id: copy_observer=member;break
		if copy_observer.is_empty(): continue
		apply(copy,candidate,copy_observer,location)
		var assignments: Array=[]
		var west:=0;var east:=0
		for member: Dictionary in team(copy,copy_observer):
			var points: PackedVector2Array=copy.nav.get_point_path(copy._nearest_open(copy._cell(member.pos)),copy._nearest_open(copy._cell(member.target)))
			var length:=0.0
			for i in range(1,points.size()): length+=points[i-1].distance_to(points[i])
			var seconds: float=length/guard_speed(member.role)
			assignments.append({"id":member.id,"from":member.pos,"target":member.target,"role":member.role,"seconds":seconds})
			if member.role not in ["sentry","block"]:
				if member.target.x<0: west+=1
				else: east+=1
		forecasts.append({"action":candidate,"assignments":assignments,"west":west,"east":east})
	return forecasts

static func forecast_facts(game, forecasts: Array) -> Array:
	var parts: PackedStringArray=[]
	var pair: String=""
	for plan: Dictionary in forecasts:
		parts.append("%s=%d/%d"%[plan.action,plan.west,plan.east])
		if plan.action=="paired_inspection":
			for assignment: Dictionary in plan.assignments:
				if assignment.role=="support":
					pair="paired_inspection: %s relocates from %s to %s, est. %.1fs travel before cover is ready. The inspecting guard waits for support."%[assignment.id,game._zone(assignment.from),game._zone(assignment.target),assignment.seconds]
	var result: Array=[{"id":"plan-posts","fact":("Projected mobile posts west/east, excluding sentries/exit guards: "+"; ".join(parts)+". These are assignments, not intruder sightings.").left(240)}]
	if not pair.is_empty(): result.append({"id":"plan-pair","fact":pair.left(240)})
	return result

static func forecast_text(forecasts: Array, selected: String) -> String:
	for plan: Dictionary in forecasts:
		if plan.action!=selected: continue
		var lines: PackedStringArray=[]
		for assignment: Dictionary in plan.assignments:
			var place: String="西" if assignment.target.x<0 else "東"
			var job: String="守備" if assignment.role in ["sentry","block"] else "機動"
			lines.append("%s→%s・%s 約%.0f秒"%[assignment.id,place,job,assignment.seconds])
		return "\n".join(lines)
	return ""

static func observe(game, guard: Dictionary, kind: String, point: Vector2, fact: String) -> void:
	if not guard.has("events"): guard.events = []
	for previous: Dictionary in guard.events:
		if previous.kind==kind and game.time-previous.time<0.3 and previous.point.distance_to(point)<0.5: return
	game._fact(guard, fact)
	guard.events.append({"time":game.time,"kind":kind,"point":point,"fact":fact})
	while guard.events.size() > 18: guard.events.pop_front()
	if kind in ["contact","gunfire","injury","missing"]:
		guard.trouble = {"point":point,"time":game.time,"kind":kind}
		guard.alert_until=game.time+25.0

static func observations(game, guard: Dictionary, trigger: String, point: Vector2, forecasts: Array=[]) -> Array:
	var result: Array = []
	var events: Array = guard.get("events", [])
	var recent: Array = []
	for event: Dictionary in events:
		if game.time - event.time < 90: recent.append(event)
	var plan_facts: Array=forecast_facts(game,forecasts) if not forecasts.is_empty() else []
	var history_limit: int=8-plan_facts.size()
	if recent.is_empty():
		result = guard.facts.slice(maxi(0,guard.facts.size()-history_limit)).duplicate(true)
	else:
		for i in range(maxi(0,recent.size()-history_limit),recent.size()):
			var event: Dictionary = recent[i]
			result.append({"id":"history%d"%i,"fact":("%ds ago: "%int(game.time-event.time)+event.fact).left(240)})
	var members: Array = team(game,guard)
	var posts: PackedStringArray = []
	for member: Dictionary in members:
		posts.append("%s %s at %s"%[member.id,member.role,game._zone(member.pos)])
	result.append({"id":"context-event","fact":"Current event: %s at %s. Observer %s. No unseen intruder location is known."%[trigger,game._zone(point),guard.id]})
	result.append({"id":"context-squad","fact":("Responding guards: %d. Current reported posts: "%members.size()+"; ".join(posts)).left(240)})
	var seen: bool = game.time-float(guard.get("direct_seen_at",-100.0)) < 1.5
	result.append({"id":"context-contact","fact":"Direct visual contact now: %s. Empty sound inspections by this guard: %d. Guard health: %d."%[str(seen),guard.empty_checks,guard.hp]})
	var stolen := false
	for member: Dictionary in members:
		if member.missing_known: stolen=true
	result.append({"id":"context-objective","fact":"Case confirmed missing by a reporting guard: %s. Keep a sentry on the objective or an escape route; other guards can maneuver."%str(stolen)})
	result.append_array(plan_facts)
	return result

static func team(game, observer: Dictionary) -> Array:
	var members: Array = []
	for guard: Dictionary in game.guards:
		if guard.hp>0 and (guard==observer or game._can_radio(observer,guard)): members.append(guard)
	return members

static func alternate(game, observer: Dictionary, location: Vector2) -> Vector2:
	var events: Array = observer.get("events",[])
	for i in range(events.size()-1,-1,-1):
		var event: Dictionary = events[i]
		if game.time-event.time<70 and event.kind in ["contact","gunfire","injury","missing"] and event.point.distance_to(location)>6:
			return event.point
	return Vector2.INF

static func baseline(game, guard: Dictionary, trigger: String, candidates: Array) -> String:
	var choice := "hold_position"
	var local_empty_checks := 0
	for event: Dictionary in guard.get("events",[]):
		if event.kind=="empty" and event.point.distance_to(guard.get("current_sound",guard.pos))<3 and game.time-event.time<90: local_empty_checks+=1
	match trigger:
		"contact": choice="flank_and_cover"
		"objective_missing": choice="contain_exits"
		"lost_contact": choice="contain_exits" if guard.missing_known else "sweep_last_known"
		"report": choice="paired_inspection"
		"noise":
			if game.time-guard.seen_at<5 or guard.role in ["block","sentry"]: choice="hold_position"
			elif local_empty_checks>=1 and alternate(game,guard,guard.get("current_sound",guard.pos))!=Vector2.INF: choice="counter_watch"
			elif local_empty_checks>0: choice="hold_position"
			elif guard.get("trouble",{}).get("time",-100.0)>game.time-12: choice="paired_inspection"
			else: choice="inspect"
	return choice if choice in candidates else str(candidates[0])

static func evidence_text(game, guard: Dictionary) -> String:
	var events: Array=guard.get("events",[])
	var lines: PackedStringArray=[]
	var names: Dictionary={"noise":"物音", "empty":"調べたが無人", "contact":"侵入者を目撃", "gunfire":"銃声の報告", "injury":"被弾", "missing":"ケース紛失", "lost_contact":"視界を失う"}
	for i in range(maxi(0,events.size()-3),events.size()):
		var event: Dictionary=events[i]
		var place: String="西" if event.point.x<0 else "東"
		lines.append("%d秒前・%s：%s"%[int(game.time-event.time),place,names.get(event.kind,event.kind)])
	return "\n".join(lines)

static func assign(game, guard: Dictionary, role: String, target: Vector2, duration: float=14.0) -> void:
	guard.role=role
	guard.target=game.nav.get_point_position(game._nearest_open(game._cell(target)))
	guard.path_time=-10.0
	guard.wait=0.0
	guard.order_until=game.time+duration
	guard.order_arrived=false
	guard.order_duration=duration
	guard.partner=""
	guard.erase("watch_point")
	guard.erase("flank_report_at")

static func flank_destination(game, guard: Dictionary, observed: Vector2) -> Vector2:
	# Intercept the observed escape approach, not the unseen player's position.
	var exit_pos: Vector2=game.EXITS[0]
	for candidate: Vector2 in game.EXITS:
		if observed.distance_to(candidate)<observed.distance_to(exit_pos): exit_pos=candidate
	var approach: Vector2=exit_pos-Vector2(0,2.5)
	var target: Vector2=observed.move_toward(approach,7.0)
	var open_target: Vector2=game.nav.get_point_position(game._nearest_open(game._cell(target)))
	var path: PackedVector2Array=game.nav.get_point_path(game._nearest_open(game._cell(guard.pos)),game._nearest_open(game._cell(open_target)))
	return open_target if not path.is_empty() else guard.pos

static func cover_post(game, seed: Vector2, exit_route: Vector2) -> Vector2:
	# Select a walkable angle with sight onto the known approach, using map geometry.
	# A target behind a barrier is not useful just because it is close to the gate.
	var best: Vector2=seed
	var best_cost:=INF
	var approach: Vector2=exit_route-Vector2(0,3)
	for x in range(-6,7):
		for y in range(-6,7):
			var candidate: Vector2=seed+Vector2(x,y)*0.5
			if game._blocked(candidate,0.45) or not game._clear_line(candidate,approach,false): continue
			var cost: float=candidate.distance_to(seed)+candidate.distance_to(exit_route)
			if cost<best_cost: best=candidate;best_cost=cost
	return best

static func apply(game, choice: String, observer: Dictionary, location: Vector2) -> void:
	var members: Array = team(game,observer)
	if members.is_empty(): return
	if choice=="hold_position":
		# Keep an existing useful assignment, including its support links.
		if observer.role in ["patrol","investigate"]: assign(game,observer,"watch",observer.pos,6)
		game.last_plan=choice
		game.plan_markers_refresh()
		return
	var reserve: Dictionary = {}
	if members.size()>=3:
		var ordered: Array=members.duplicate()
		ordered.sort_custom(func(a,b):return a.pos.distance_to(game.CASE_POS)<b.pos.distance_to(game.CASE_POS))
		for guard: Dictionary in ordered:
			if guard!=observer: reserve=guard;break
		if reserve.is_empty(): reserve=ordered[0]
	var free: Array=members.filter(func(g):return g!=reserve)
	if free.is_empty(): free=members.duplicate()
	var missing := false
	for guard: Dictionary in members:
		if guard.missing_known: missing=true
	var exit_index: int = 0 if location.x<0 else 1
	if not reserve.is_empty() and reserve.role not in ["sentry","ambush","block"]:
		assign(game,reserve,"sentry",game.EXITS[exit_index]-Vector2(0,2) if missing else Vector2(10,-2))
		reserve.watch_point=game.EXITS[exit_index]-Vector2(0,4) if missing else game.CASE_POS+Vector2(0,4)
	match choice:
		"inspect": assign(game,observer,"investigate",location)
		"paired_inspection":
			var partners: Array=free.filter(func(g):return g!=observer)
			partners.sort_custom(func(a,b):return a.pos.distance_to(location)<b.pos.distance_to(location))
			if partners.is_empty(): assign(game,observer,"watch",observer.pos)
			else:
				var buddy: Dictionary=partners[0]
				var approach: Vector2=(observer.pos-location).normalized()
				if approach.length()<0.1: approach=Vector2.DOWN
				assign(game,buddy,"support",location+approach*3.0+Vector2(-approach.y,approach.x)*1.4)
				assign(game,observer,"wait_cover",location+approach*3.2)
				observer.partner=buddy.id
				observer.investigation=location
				game._log("%s：%sの援護配置を待って進む"%[observer.id,buddy.id])
		"hold_position": assign(game,observer,"watch",observer.pos)
		"sweep_last_known":
			for i in range(free.size()): assign(game,free[i],"search",location+Vector2(float(i)*2-1,0))
		"contain_exits":
			members.sort_custom(func(a,b):return a.pos.distance_to(game.EXITS[exit_index])<b.pos.distance_to(game.EXITS[exit_index]))
			for i in range(members.size()):
				assign(game,members[i],"block" if i<2 else "search",game.EXITS[(exit_index+i)%2]-Vector2(0,2) if i<2 else location)
				if i<2: members[i].watch_point=game.EXITS[(exit_index+i)%2]-Vector2(0,4)
		"flank_and_cover":
			free.sort_custom(func(a,b):return a.pos.distance_to(location)<b.pos.distance_to(location))
			for i in range(free.size()):
				var known: Vector2=free[i].last_seen if game.time-float(free[i].seen_at)<2.0 else location
				assign(game,free[i],"pursue" if i==0 else "flank",known if i==0 else flank_destination(game,free[i],known))
				# A delayed decision must not overwrite a newer sighting or radio report.
				if game.time-float(free[i].seen_at)>=2.0:
					free[i].last_seen=location
					free[i].seen_at=game.time-0.5
				if i>0: free[i].flank_report_at=-100.0
		"counter_watch":
			var other: Vector2=alternate(game,observer,location)
			if other==Vector2.INF:
				apply(game,"paired_inspection",observer,location)
				return
			var away: Vector2=(observer.pos-location).normalized()
			if away.length()<0.1: away=Vector2.DOWN
			assign(game,observer,"watch",location+away*4.0)
			for guard: Dictionary in free:
				if guard!=observer:
					# Watch the approach to the earlier trouble area, not the unseen player.
					var exit_route: Vector2=game.EXITS[0 if other.x<0 else 1]-Vector2(0,2)
					var post: Vector2=cover_post(game,other.lerp(exit_route,0.5),exit_route)
					assign(game,guard,"ambush",post)
					guard.watch_point=other
			game._log("音源へ集中せず、以前の別地点の報告と分担して警戒")
	game.last_plan=choice
	game.plan_markers_refresh()

static func tick(game, guard: Dictionary) -> void:
	if guard.has("order_arrived") and not guard.order_arrived and guard.pos.distance_to(guard.target)<0.8:
		guard.order_arrived=true
		guard.order_until=game.time+float(guard.get("order_duration",14.0))
	if guard.role=="flank":
		if game.time-float(guard.seen_at)>4.0:
			assign(game,guard,"search",guard.last_seen,5)
		elif game.time-float(guard.get("flank_report_at",-100.0))>=0.75:
			guard.flank_report_at=game.time
			var next_target: Vector2=flank_destination(game,guard,guard.last_seen)
			if guard.target.distance_to(next_target)>1.0:
				guard.target=next_target
				guard.path_time=-10.0
			if guard.pos.distance_to(guard.target)<0.8:
				# Reaching the intercept is a transition to engagement, not a ten-second wait.
				assign(game,guard,"pursue",guard.last_seen,5)
	if guard.role=="wait_cover":
		var buddy: Dictionary={}
		for member: Dictionary in game.guards:
			if member.id==guard.get("partner",""): buddy=member
		if buddy.is_empty() or buddy.hp<=0 or not game._can_radio(guard,buddy):
			assign(game,guard,"watch",guard.pos,5)
		elif buddy.pos.distance_to(buddy.target)<1.0:
			assign(game,guard,"investigate",guard.investigation)
			game._log(guard.id+"：援護配置を確認、進む")
	if guard.role in ["watch","ambush","sentry","block","wait_cover"] and game.time>float(guard.get("order_until",INF)):
		assign(game,guard,"patrol",guard.patrol[guard.patrol_i])
	if guard.role in ["ambush","sentry","block"] and guard.has("watch_point") and guard.pos.distance_to(guard.target)<0.8:
		guard.face=(guard.get("watch_point",guard.pos+Vector2.UP)-guard.pos).normalized()
		# A guard at a post scans its surroundings instead of staring forever.
		if guard.role=="ambush": guard.face=guard.face.rotated(float(guard.wait)*0.9)
		else: guard.face=guard.face.rotated(sin(float(guard.wait)*0.75)*0.65)
