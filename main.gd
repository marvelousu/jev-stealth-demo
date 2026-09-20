extends Node3D

const Level = preload("res://level.gd")
const Tactics = preload("res://tactics.gd")
const Replay = preload("res://replay.gd")
const Mission = preload("res://mission.gd")
const Briefing = preload("res://briefing.gd")
const DecisionHistory = preload("res://decision_history.gd")
const DecisionGate = preload("res://decision_gate.gd")
const MissionFeedback = preload("res://mission_feedback.gd")
const Explanation = preload("res://explanation.gd")
const TacticalView = preload("res://tactical_view.gd")
const COMPARISON_WAIT := 1.5
# Distribution builds embed a public decision-service URL, never a Jev API key.
var service_url: String = str(ProjectSettings.get_setting("jev/service_url", "http://127.0.0.1:8789")).trim_suffix("/")
const CASE_POS = Vector2(10, -6)
const POWER_POS = Vector2(-10, -6)
const EXITS = [Vector2(-11, 9), Vector2(11, 9)]
const ROLE_NAMES = {"patrol":"巡回", "investigate":"音源を確認", "support":"援護", "block":"出口を警戒", "flank":"回り込む", "search":"最終目撃を捜索", "pursue":"追跡", "down":"行動不能", "wait_cover":"援護待ち", "watch":"音源を監視", "ambush":"別経路を待つ", "sentry":"警戒を維持"}
const CHOICE_NAMES = {"inspect":"一人で確認", "paired_inspection":"確認役と援護役", "hold_position":"持ち場を維持", "sweep_last_known":"最後に見た場所を捜索", "contain_exits":"出口の封鎖", "flank_and_cover":"追跡・側面・援護", "counter_watch":"囮を警戒・別経路へ先回り"}

var level: Node3D
var player: Node3D
var player_pos := Vector2(-11, 8)
var player_hp := 100.0
var aim_pos := Vector2.ZERO
var guards: Array[Dictionary] = []
var nav := AStarGrid2D.new()
var time := 0.0
var active := false
var music_player: AudioStreamPlayer
var music_button: Button
var music_muted := false
var music_settings_path := "user://audio.cfg"
var finished := false
var has_case := false
var power_on := true
var was_detected := false
var noise_charges := 6
var smoke_charges := 3
var shot_cooldown := 0.0
var tool_cooldown := 0.0
var mode := "jev"
var service_status := "接続を確認中"
var decision_source := "まだ判断なし"
var decision_name := "重要な出来事で判断"
var api_calls := 0
var api_sent := 0
var api_tokens := 0
var tactical_assist := false
var pending := false
var queued_decision: Dictionary = {}
var pending_age := 0.0
var revision := 0
var run_id := 0
var event_id := 0
var request_id := 0
var last_decision_time := -100.0
var last_contact_request := -100.0
var smokes: Array[Dictionary] = []
var sound_markers: Array[Node3D] = []
var event_log: Array[String] = []
var ui_root: Control
var headline: Label
var objective: Label
var vitals: Label
var prompt_label: Label
var ai_label: Label
var log_label: Label
var detail_panel: PanelContainer
var intro: PanelContainer
var result_panel: PanelContainer
var result_label: Label
var pause_label: Label
var inspect_enabled := true
var ui_clock := 0.0
var qa_mode := false
var qa_phase := 0
var qa_clock := 0.0
var paused := false
var sight_mesh := ImmediateMesh.new()
var sight_node: MeshInstance3D
var sight_clock := 0.0
var last_plan := ""
var last_evidence := ""
var last_confidence := 0.0
var plan_nodes: Array[Node3D] = []
var trace: Array = []
var replay = Replay.new()
var comparison_label: Label
var devices: Array = []
var plan_mesh := ImmediateMesh.new()
var plan_mesh_node: MeshInstance3D
var plan_clock := 0.0

var ammo := 6
var interaction_progress := 0.0
var interaction_kind := ""
var interaction_origin := Vector2.ZERO
var last_damage_at := -100.0
var damage_flash := 0.0
var damage_taken := 0.0
var first_damage_at := -1.0
var lethal_damage_at := -1.0
var detected_count := 0
var success := false
var last_baseline := ""
var last_forecast := ""
var history = DecisionHistory.new()
var comparison_gate = DecisionGate.new()
var feedback = MissionFeedback.new()
var explanation = Explanation.new()
var tactical_view: Control
var guided_comparison := false
var guided_pauses: Dictionary = {}
var feedback_panel: PanelContainer
var feedback_label: Label
var health_bar: ProgressBar
var interaction_bar: ProgressBar
var threat_label: Label
var damage_overlay: ColorRect

func movement_speed(crouching: bool) -> float:
	return Mission.speed(self,crouching)

func _ready() -> void:
	for binding in [["move_left",KEY_A],["move_right",KEY_D],["move_up",KEY_W],["move_down",KEY_S],["crouch",KEY_SHIFT],["interact",KEY_E]]:
		if not InputMap.has_action(binding[0]):
			InputMap.add_action(binding[0])
			var key:=InputEventKey.new()
			key.physical_keycode=binding[1]
			InputMap.action_add_event(binding[0],key)
	qa_mode = "--qa" in OS.get_cmdline_user_args()
	level = Level.new()
	add_child(level)
	plan_mesh_node=MeshInstance3D.new()
	plan_mesh_node.mesh=plan_mesh
	var plan_material:=StandardMaterial3D.new()
	plan_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	plan_material.vertex_color_use_as_albedo=true
	plan_mesh_node.material_override=plan_material
	add_child(plan_mesh_node)
	_build_nav()
	_build_ui()
	history.build(self)
	explanation.build(self)
	tactical_view=TacticalView.new()
	tactical_view.game=self
	ui_root.add_child(tactical_view)
	sight_node = MeshInstance3D.new()
	sight_node.mesh = sight_mesh
	var sight_material := StandardMaterial3D.new()
	sight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sight_material.vertex_color_use_as_albedo = true
	sight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sight_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	sight_node.material_override = sight_material
	add_child(sight_node)
	_reset()
	_start_music()
	_check_service()
	if qa_mode:
		active = true
		intro.hide()
		_log("自動検証：入力・状態遷移・描画の確認")
		get_tree().create_timer(13.0).timeout.connect(func():get_tree().quit())

func _build_nav() -> void:
	nav.region = Rect2i(0, 0, 61, 41)
	nav.cell_size = Vector2(0.5, 0.5)
	nav.offset = Vector2(-15, -10)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for ix in range(61):
		for iz in range(41):
			var p := Vector2(ix * 0.5 - 15, iz * 0.5 - 10)
			nav.set_point_solid(Vector2i(ix, iz), _blocked(p, 0.42))

func _reset() -> void:
	if explanation.is_open(): explanation.close(self)
	comparison_gate.clear()
	if is_instance_valid(history.panel): history.close(self)
	run_id += 1
	revision += 1
	last_plan=""
	last_baseline=""
	last_forecast=""
	last_evidence=""
	trace.clear()
	feedback.reset()
	devices.clear()
	for marker in plan_nodes:
		if is_instance_valid(marker): marker.queue_free()
	plan_nodes.clear()
	time = 0
	player_hp = 100
	player_pos = Vector2(-11, 8)
	has_case = false
	power_on = true
	was_detected = false
	noise_charges = 6
	smoke_charges = 3
	shot_cooldown = 0
	tool_cooldown = 0
	finished = false
	Mission.reset(self)
	pending = false
	queued_decision.clear()
	last_decision_time = -100
	last_contact_request = -100
	decision_name = "重要な出来事で判断"
	decision_source = "まだ判断なし"
	for g in guards:
		g.node.queue_free()
	guards.clear()
	for smoke in smokes:
		smoke.node.queue_free()
	smokes.clear()
	for marker in sound_markers:
		if is_instance_valid(marker): marker.queue_free()
	sound_markers.clear()
	if is_instance_valid(player): player.queue_free()
	player = level.make_actor(Color("71e4cb"), "YOU")
	add_child(player)
	player.get_node("RoleLabel").text = ""
	var player_ring: MeshInstance3D = level.make_ring(Color("71e4cb"),0.58)
	player.add_child(player_ring)
	player_ring.position.y = 0.06
	player.position = _v3(player_pos)
	var starts := [Vector2(-8, 0), Vector2(2, 2), Vector2(10, -5)]
	var paths := [[Vector2(-8, 0),Vector2(-4, 4),Vector2(-11, 3)], [Vector2(2, 2),Vector2(8, 3),Vector2(3, 6)], [Vector2(10, -5),Vector2(7, -4),Vector2(10, -3)]]
	for i in range(3):
		var id: String = ["A", "B", "C"][i]
		var actor: Node3D = level.make_actor(Color("f7ac77"), id)
		add_child(actor)
		actor.position = _v3(starts[i])
		guards.append({"id":id, "node":actor, "pos":starts[i], "face":Vector2(0,-1), "hp":100.0, "role":"patrol", "target":starts[i], "patrol":paths[i], "patrol_i":0, "path":PackedVector2Array(), "path_time":-10.0, "detect":0.0, "last_seen":starts[i], "seen_at":-100.0, "reported_at":-100.0, "fire":0.0, "wait":0.0, "facts":[], "empty_checks":0, "noise_id":-1, "missing_known":false, "events":[], "partner":"", "order_until":0.0})
	level.case_visual.visible = true
	level.generator_visual.visible = true
	event_log.clear()
	_log("ケースを回収し、南側のどちらかの出口へ")
	result_panel.hide()
	paused = false
	pause_label.hide()
	_update_ui()

func _physics_process(delta: float) -> void:
	if not active or finished or paused: return
	time += delta
	comparison_gate.tick(time)
	var tick_run:=run_id
	replay.tick(self,delta)
	# Starting the next comparison phase resets all actors. Do not advance its
	# guards once in the tail of the preceding phase before its first event.
	if run_id!=tick_run or not active: return
	for device: Dictionary in devices.duplicate():
		if time>=device.next:
			_noise(device.pos,"Heard the same short electronic chirp repeat")
			device.remaining-=1
			device.next+=8.0
			if device.remaining<=0: devices.erase(device)
	shot_cooldown = maxf(0, shot_cooldown - delta)
	tool_cooldown = maxf(0, tool_cooldown - delta)
	var direction := Input.get_vector("move_left","move_right","move_up","move_down")
	if replay.playing or replay.comparing: direction=Vector2.ZERO
	var crouching := Input.is_action_pressed("crouch")
	var speed := movement_speed(crouching)
	if direction.length() > 0:
		player_pos = _move(player_pos, direction.normalized() * speed * delta)
	player.position = _v3(player_pos, 0.035 * sin(time * 13) if direction.length() > 0 else 0)
	_update_aim()
	var aim_dir := aim_pos - player_pos
	if aim_dir.length() > 0.1: player.rotation.y = atan2(-aim_dir.x, -aim_dir.y)
	if not replay.playing and not replay.comparing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and shot_cooldown <= 0 and not _mouse_over_ui():
		_shoot_player()
	for g in guards:
		_update_guard(g, delta, crouching)
	_update_smoke(delta)
	sight_clock += delta
	if sight_clock > 0.16:
		sight_clock = 0
		_draw_senses(crouching)
		Mission.aim_lines(self)
	if pending: pending_age += delta
	if not pending and not queued_decision.is_empty() and time-last_decision_time>=1.0:
		var queued: Dictionary=queued_decision.duplicate()
		queued_decision.clear()
		_request_decision(queued.observer,queued.trigger,queued.location,queued.candidates)
	Mission.tick(self,delta)
	ui_clock += delta
	if ui_clock > 0.12:
		ui_clock = 0
		_update_ui()
	if qa_mode: _qa_tick(delta)
	plan_clock+=delta
	if plan_clock>0.25:
		plan_clock=0
		_update_plan_lines()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode==KEY_B:
		_toggle_music()
		return
	if explanation.is_open():
		if event.physical_keycode in [KEY_F1,KEY_ESCAPE]: explanation.close(self)
		elif event.physical_keycode==KEY_F10: start_guided_comparison()
		return
	if history.panel.visible:
		if event.physical_keycode in [KEY_H,KEY_ESCAPE]: history.close(self)
		return
	if event.physical_keycode==KEY_F1:
		explanation.toggle(self)
		return
	if event.physical_keycode==KEY_F10:
		start_guided_comparison()
		return
	if event.physical_keycode==KEY_H:
		history.toggle(self)
		return
	if Mission.observation_mode(self) and event.physical_keycode in [KEY_Q,KEY_F,KEY_G,KEY_E]: return
	match event.physical_keycode:
		KEY_ENTER:
			if not active:
				active = true
				intro.hide()
		KEY_R:
			guided_comparison=false
			replay.stop()
			_reset()
			active = true
			paused = false
			intro.hide()
		KEY_TAB:
			inspect_enabled = not inspect_enabled
			detail_panel.visible = inspect_enabled
			_update_plan_lines()
		KEY_M:
			guided_comparison=false
			var was_observing: bool=Mission.observation_mode(self)
			if was_observing: replay.stop()
			mode = "rules" if mode == "jev" else "jev"
			if was_observing:
				_reset();active=true;intro.hide()
			revision += 1
			_log("判断方式を切替：" + ("Jev" if mode == "jev" else "ルール"))
			_update_ui()
		KEY_ESCAPE:
			paused = not paused
			pause_label.visible = paused
		KEY_F8:
			guided_comparison=false
			replay.start_comparison(self)
		KEY_F9:
			replay.change_variant(self)
		KEY_F6:
			guided_comparison=false
			replay.toggle_record(self)
		KEY_F7:
			guided_comparison=false
			replay.play_recording(self)
		KEY_F:
			if active and not finished and not paused: _throw_noise()
		KEY_Q:
			if active and not finished and not paused: _throw_noise(false)
		KEY_G:
			if active and not finished and not paused: _throw_smoke()
		KEY_E:
			if active and not finished and not paused: _interact()

func _update_aim() -> void:
	if replay.playing or replay.comparing: return
	var camera: Camera3D = level.camera
	var mouse := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit != null: aim_pos = Vector2(hit.x, hit.z)

func _mouse_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE

func _move(from: Vector2, change: Vector2) -> Vector2:
	var p := from
	var nx := Vector2(clampf(p.x + change.x, -14.4, 14.4), p.y)
	if not _blocked(nx, 0.36): p = nx
	var nz := Vector2(p.x, clampf(p.y + change.y, -9.4, 9.6))
	if not _blocked(nz, 0.36): p = nz
	return p

func _blocked(p: Vector2, radius: float) -> bool:
	for rect: Rect2 in level.obstacles:
		if rect.grow(radius).has_point(p): return true
	return false

func _clear_line(a: Vector2, b: Vector2, smoke_blocks := true) -> bool:
	for r: Rect2 in level.obstacles:
		if r.has_point(a) or r.has_point(b): return false
		var corners := [r.position, Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]
		for i in range(4):
			if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4]) != null: return false
	if smoke_blocks:
		for smoke in smokes:
			if Geometry2D.get_closest_point_to_segment(smoke.pos,a,b).distance_to(smoke.pos) < 2.4: return false
	return true

func _sees(g: Dictionary, p: Vector2, limit: float) -> bool:
	var difference: Vector2 = p - g.pos
	if difference.length() > limit: return false
	if difference.length() > 1.4 and g.face.dot(difference.normalized()) < 0.35: return false
	return _clear_line(g.pos,p)

func sight_range(g: Dictionary, crouching: bool) -> float:
	return 8.0 if time<float(g.get("alert_until",-100.0)) or time-float(g.get("direct_seen_at",-100.0))<6 else (4.6 if crouching else 7.6)

func _draw_senses(crouching: bool) -> void:
	sight_mesh.clear_surfaces()
	sight_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for g in guards:
		if g.hp <= 0: continue
		var distance := sight_range(g,crouching)
		var color := Color(1.0,0.30,0.18,0.15) if g.detect >= 1 else Color(0.95,0.68,0.30,0.065)
		var previous: Vector2 = g.pos
		for i in range(25):
			var direction: Vector2 = g.face.rotated(-acos(0.35)+2*acos(0.35)*float(i)/24)
			var endpoint: Vector2 = g.pos+direction*distance
			for step in range(1,25):
				var probe: Vector2 = g.pos+direction*distance*float(step)/24
				if not _clear_line(g.pos,probe):
					endpoint=g.pos+direction*distance*float(step-1)/24
					break
			if i>0:
				for p: Vector2 in [g.pos,previous,endpoint]:
					sight_mesh.surface_set_color(color)
					sight_mesh.surface_add_vertex(_v3(p,0.045))
			previous=endpoint
	# A degenerate triangle keeps the surface valid when every guard is down.
	for i in range(3):
		sight_mesh.surface_set_color(Color.TRANSPARENT)
		sight_mesh.surface_add_vertex(Vector3.ZERO)
	sight_mesh.surface_end()

func _update_guard(g: Dictionary, delta: float, crouching: bool) -> void:
	if g.hp <= 0: return
	Tactics.tick(self,g)
	var visible := _sees(g, player_pos, sight_range(g,crouching))
	g.detect = clampf(g.detect + delta * (1.5 if visible else -0.85),0,1)
	if visible and g.detect >= 1:
		if not was_detected: _sfx("alert")
		if time-float(g.get("direct_seen_at",-100.0))>1.5:
			detected_count+=1
			feedback.record(self,"contact",g.id+"に発見された（"+_place(player_pos)+"）",{"guard":g.id})
		g.direct_seen_at=time
		was_detected = true
		g.last_seen = player_pos
		g.seen_at = time
		if time-float(g.get("radio_track_at",-100.0))>=0.75:
			g.radio_track_at=time
			for other: Dictionary in guards:
				if other==g or other.hp<=0 or not _can_radio(g,other): continue
				other.last_seen=g.last_seen
				other.seen_at=time
		g.face = (player_pos - g.pos).normalized()
		if g.role not in ["block", "flank", "support", "sentry"]:
			g.role = "pursue"
			g.target = player_pos
		if time - g.reported_at > 5:
			g.reported_at = time
			Tactics.observe(self,g,"contact",player_pos,"Saw an armed intruder at " + _zone(player_pos))
			_report_contact(g)
			if time - last_contact_request > 7:
				last_contact_request = time
				_request_decision(g, "contact", player_pos, ["flank_and_cover","contain_exits","hold_position"])
		g.fire += delta
		if g.fire >= Mission.AIM_TIME and g.pos.distance_to(player_pos) < 8:
			g.fire = 0
			_beam(_v3(g.pos,0.9),_v3(player_pos,0.65),Color("ffa781"))
			_sfx("shot",-23)
			Mission.hurt(self,Mission.DAMAGE,g.id)
	else:
		g.fire = maxf(0,g.fire-delta*2.0)
		if g.role == "pursue":
			g.target = g.last_seen
			if time - g.seen_at > 2.5:
				g.role = "search"
				Tactics.observe(self,g,"lost_contact",g.last_seen,"Lost visual contact at "+_zone(g.last_seen)+"; only the last observed position is known")
				if not _team_has_visual_contact(g):
					_request_decision(g,"lost_contact",g.last_seen,["sweep_last_known","contain_exits","hold_position"])
	if has_case and not g.missing_known and _sees(g,CASE_POS,6):
		g.missing_known = true
		Tactics.observe(self,g,"missing",CASE_POS,"Personally saw the storage pedestal empty; the portable case is missing")
		for other: Dictionary in guards:
			if other!=g and other.hp>0 and _can_radio(g,other):
				other.missing_known=true
				Tactics.observe(self,other,"missing",CASE_POS,"Received "+g.id+" report: personally confirmed that the storage case is missing")
		_log(g.id + "：保管ケースがない。報告する！")
		# Record the missing case, but do not replace a fresh visual-contact response
		# with a slower inventory report while the intruder is still being tracked.
		if not _team_has_visual_contact(g):
			_request_decision(g,"objective_missing",CASE_POS,["contain_exits","sweep_last_known","hold_position"])
	if g.role == "patrol":
		if g.pos.distance_to(g.target) < 0.6:
			g.patrol_i = (int(g.patrol_i) + 1) % g.patrol.size()
			g.target = g.patrol[g.patrol_i]
	var distance: float = g.pos.distance_to(g.target)
	if distance > 0.55:
		var next := _next_step(g)
		var direction: Vector2 = next - g.pos
		if direction.length() > 0.08:
			var speed := Tactics.guard_speed(g.role)
			g.pos = _move(g.pos, direction.normalized() * speed * delta)
			if not visible: g.face = direction.normalized()
		g.wait = 0
	else:
		g.wait += delta
		if not visible and g.role not in ["ambush","sentry","block"]: g.face = g.face.rotated(delta * 0.42)
		if g.role == "investigate" and g.wait > 2.3 and not visible:
			g.empty_checks += 1
			Tactics.observe(self,g,"empty",g.target,"Inspected the sound location at "+_zone(g.target)+" and found no intruder (empty inspection)")
			_log(g.id + "：誰もいない……誘われたのか？")
			g.role = "patrol"
			g.wait = 0
		elif g.role in ["search","support","flank"] and g.wait > 10 and time - g.seen_at > 8:
			g.role = "patrol"
			g.wait = 0
	g.node.position = _v3(g.pos,0.025 * sin(time*10) if distance>0.6 else 0)
	g.node.rotation.y = atan2(-g.face.x,-g.face.y)
	var text: String = g.id + " · " + ROLE_NAMES.get(g.role,g.role)
	if g.detect > 0 and g.detect < 1: text += " ？"
	if g.fire > 0.5: text += " ▸"
	g.node.get_node("RoleLabel").text = text

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(roundi((p.x+15)*2),0,60),clampi(roundi((p.y+10)*2),0,40))

func _nearest_open(cell: Vector2i) -> Vector2i:
	if not nav.is_point_solid(cell): return cell
	for radius in range(1,10):
		for dx in range(-radius,radius+1):
			for dy in range(-radius,radius+1):
				var p := cell+Vector2i(dx,dy)
				if nav.is_in_boundsv(p) and not nav.is_point_solid(p): return p
	return cell

func _next_step(g: Dictionary) -> Vector2:
	if time - g.path_time > 0.55 or g.path.is_empty():
		g.path_time = time
		var start := _nearest_open(_cell(g.pos))
		var end := _nearest_open(_cell(g.target))
		g.path = nav.get_point_path(start,end)
	while not g.path.is_empty() and g.pos.distance_to(g.path[0]) < 0.4:
		g.path.remove_at(0)
	return g.path[0] if not g.path.is_empty() else g.pos

func _can_radio(a: Dictionary, b: Dictionary) -> bool:
	return power_on or a.pos.distance_to(b.pos) < 5

func _team_has_visual_contact(observer: Dictionary) -> bool:
	for member: Dictionary in Tactics.team(self,observer):
		if time-float(member.get("direct_seen_at",-100.0))<2.0: return true
	return false

func _report_contact(source: Dictionary) -> void:
	for other in guards:
		if other == source or other.hp <= 0 or not _can_radio(source,other): continue
		other.last_seen = source.last_seen
		other.seen_at = source.seen_at
		Tactics.observe(self,other,"contact",source.last_seen,"Received guard " + source.id + " report of an intruder at " + _zone(source.last_seen))
		if other.role in ["patrol","investigate","search"]:
			other.role = "search"
			other.target = source.last_seen

func _throw_noise(repeated: bool=true) -> void:
	if noise_charges <= 0 or tool_cooldown > 0: return
	replay.event(self,"noise" if repeated else "noise_single")
	noise_charges -= 1
	tool_cooldown = 0.7
	var target := player_pos + (aim_pos-player_pos).limit_length(9)
	target.x = clampf(target.x,-13.8,13.8)
	target.y = clampf(target.y,-8.8,8.8)
	if _blocked(target,0.2): target = player_pos
	feedback.record(self,"noise","反復物音を設置" if repeated else "単発物音を投げた")
	_noise(target,"Heard a metallic impact followed by a short electronic chirp")
	# A standard delayed noisemaker creates repeated distractions during free play too.
	if repeated: devices.append({"pos":target,"next":time+8.0,"remaining":2})

func _noise(pos: Vector2, description: String) -> void:
	_sfx("noise")
	event_id += 1
	var ring: MeshInstance3D = level.make_ring(Color("ffd06e"),1)
	add_child(ring)
	ring.position = _v3(pos,0.12)
	sound_markers.append(ring)
	var tween := create_tween()
	tween.tween_property(ring,"scale",Vector3(2.5,1,2.5),1.1)
	tween.tween_callback(ring.queue_free)
	var listeners: Array[Dictionary] = []
	for g in guards:
		if g.hp > 0 and g.pos.distance_to(pos) < 12:
			Tactics.observe(self,g,"noise",pos,description + " at " + _zone(pos))
			g.current_sound=pos
			g.noise_id = event_id
			listeners.append(g)
	listeners.sort_custom(func(a,b):return a.pos.distance_to(pos)<b.pos.distance_to(pos))
	if not listeners.is_empty():
		var observer: Dictionary = listeners[0]
		for other: Dictionary in guards:
			if other.hp>0 and other not in listeners and _can_radio(observer,other):
				Tactics.observe(self,other,"noise",pos,"Received "+observer.id+" report: disturbance at "+_zone(pos))
		if observer.role not in ["pursue","flank","block","sentry"] and time-observer.seen_at>4:
			if observer.role in ["patrol","investigate"]:
				observer.role = "investigate"
				observer.target = pos
				observer.wait = 0
			_request_decision(observer,"noise",pos,["inspect","paired_inspection","hold_position","counter_watch"])
	_log("物音が施設内へ響いた")

func _throw_smoke() -> void:
	replay.event(self,"smoke")
	if smoke_charges <= 0 or tool_cooldown > 0: return
	_sfx("smoke")
	smoke_charges -= 1
	tool_cooldown = 0.7
	var target := player_pos+(aim_pos-player_pos).limit_length(5)
	var container := Node3D.new()
	add_child(container)
	container.position = _v3(target)
	for i in range(7):
		var puff := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.2
		mesh.height = 1.8
		puff.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.40,0.52,0.61,0.37)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff.material_override = mat
		puff.position = Vector3(cos(i*2.4)*1.25,0.8+float(i%3)*0.18,sin(i*2.4)*1.25)
		container.add_child(puff)
	smokes.append({"pos":target,"node":container,"life":5.0})
	feedback.record(self,"smoke","煙幕を使用（残り%d）"%smoke_charges)
	_log("煙幕で視線を切る。敵は最後に見た場所へ")

func _update_smoke(delta: float) -> void:
	for i in range(smokes.size()-1,-1,-1):
		smokes[i].life -= delta
		if smokes[i].life < 1:
			smokes[i].node.scale = Vector3.ONE * maxf(0.01,smokes[i].life)
		if smokes[i].life <= 0:
			smokes[i].node.queue_free()
			smokes.remove_at(i)

func _interact() -> void:
	replay.event(self,"interact")
	if player_pos.distance_to(POWER_POS)<2 and _clear_line(player_pos,POWER_POS,false):
		power_on = not power_on
		feedback.record(self,"power","無線の中継電源をON" if power_on else "無線の中継電源をOFF")
		revision += 1
		_noise(POWER_POS,"Heard the relay generator stop" if not power_on else "Heard the relay generator restart")
		_log("中継電源OFF：敵の無線が途絶え、近くの声だけが届く" if not power_on else "中継電源ON：敵の無線が復旧")
	_update_ui()

func _shoot_player() -> void:
	if ammo<=0 or shot_cooldown>0 or finished or paused: return
	replay.event(self,"shot")
	feedback.record(self,"shot","プレイヤーが発砲",{"position":[player_pos.x,player_pos.y],"aim":[aim_pos.x,aim_pos.y]})
	ammo-=1
	_sfx("shot")
	shot_cooldown = 0.5
	var direction := (aim_pos-player_pos).normalized()
	if direction.length()<0.1: return
	var end := player_pos+direction*9
	var hit_guard: Dictionary = {}
	var closest := 9.0
	for g in guards:
		if g.hp<=0: continue
		var diff: Vector2 = g.pos-player_pos
		var along := diff.dot(direction)
		if along>0 and along<closest and absf(diff.cross(direction))<0.65 and _clear_line(player_pos,g.pos,true):
			closest=along
			hit_guard=g
	if not hit_guard.is_empty():
		end=hit_guard.pos
		hit_guard.hp-=25
		Tactics.observe(self,hit_guard,"injury",hit_guard.pos,"Was hit by a shot at "+_zone(hit_guard.pos)+"; shooter position is not known")
		if hit_guard.hp<=0:
			hit_guard.role="down"
			hit_guard.node.rotation.z=PI/2
			hit_guard.node.get_node("RoleLabel").text=hit_guard.id+" · 行動不能"
			feedback.record(self,"down",hit_guard.id+"を行動不能にした")
			_log(hit_guard.id+" が倒れた。まだ見ていない敵には伝わらない")
	# End the tracer at the first solid surface rather than drawing through walls.
	for i in range(1,73):
		var probe := player_pos+direction*float(i)*0.25
		if player_pos.distance_to(probe)>player_pos.distance_to(end): break
		if _blocked(probe,0):
			end=probe
			break
	_beam(_v3(player_pos,0.85),_v3(end,0.85),Color("91f6e1"))
	var listeners: Array[Dictionary]=[]
	for g in guards:
		if g.hp>0 and g.pos.distance_to(player_pos)<12:
			listeners.append(g)
			Tactics.observe(self,g,"gunfire",player_pos,"Heard gunfire at "+_zone(player_pos))
			for other: Dictionary in guards:
				if other!=g and other.hp>0 and _can_radio(g,other):
					Tactics.observe(self,other,"gunfire",player_pos,"Received "+g.id+" report of gunfire at "+_zone(player_pos))
			if g.role=="patrol":
				g.role="search"
				g.target=player_pos
			g.face=(player_pos-g.pos).normalized()
	# A shot is a tactical event in its own right, even without a later noisemaker.
	# Pass the heard shot location once; never continuously update it to an unseen player.
	listeners.sort_custom(func(a,b):return a.pos.distance_to(player_pos)<b.pos.distance_to(player_pos))
	if not listeners.is_empty() and time-last_contact_request>4 and not _team_has_visual_contact(listeners[0]):
		_request_decision(listeners[0],"report",player_pos,["paired_inspection","sweep_last_known","hold_position"])

func _beam(a: Vector3,b: Vector3,color: Color) -> void:
	if a.distance_to(b)<0.05: return
	var beam:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=Vector3(0.055,0.045,a.distance_to(b))
	beam.mesh=mesh
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override=mat
	add_child(beam)
	beam.position=(a+b)*0.5
	beam.look_at(b,Vector3.UP)
	get_tree().create_timer(0.11).timeout.connect(beam.queue_free)

func _start_music() -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus<0:
		AudioServer.add_bus()
		bus=AudioServer.bus_count-1
		AudioServer.set_bus_name(bus,"Music")
	var settings:=ConfigFile.new()
	if settings.load(music_settings_path)==OK: music_muted=bool(settings.get_value("music","muted",false))
	AudioServer.set_bus_mute(bus,music_muted)
	music_player=AudioStreamPlayer.new()
	music_player.name="BackgroundMusic"
	var stream:=load("res://audio/bgm.ogg") as AudioStreamOggVorbis
	stream.loop=true
	music_player.stream=stream
	music_player.bus="Music"
	music_player.volume_db=-40
	add_child(music_player)
	music_player.play()
	create_tween().tween_property(music_player,"volume_db",-2.0,1.2)
	music_button.text="BGM："+("OFF" if music_muted else "ON")+" [B]"

func _toggle_music() -> void:
	music_muted=not music_muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"),music_muted)
	music_button.text="BGM："+("OFF" if music_muted else "ON")+" [B]"
	var settings:=ConfigFile.new()
	settings.set_value("music","muted",music_muted)
	settings.save(music_settings_path)

func _sfx(effect: String,volume: float=-16) -> void:
	var audio:=AudioStreamPlayer.new()
	audio.stream=load("res://audio/"+effect+".wav")
	audio.volume_db=volume
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()

func _fact(g: Dictionary,text: String) -> void:
	if not g.facts.is_empty() and g.facts.back().fact==text: return
	event_id+=1
	g.facts.append({"id":"e"+str(event_id),"fact":text})
	if g.facts.size()>8: g.facts.pop_front()

func _zone(p: Vector2) -> String:
	if Rect2(7.45,-8.55,5.1,4.55).has_point(p): return "east storage room"
	if Rect2(-12.65,-8.25,5.3,4.2).has_point(p): return "west equipment room"
	if p.y>6: return "southwest service gate" if p.x<0 else "southeast loading gate"
	return "west courtyard" if p.x<0 else "east courtyard"

func _place(p: Vector2) -> String:
	if Rect2(7.45,-8.55,5.1,4.55).has_point(p): return "東の保管庫"
	if Rect2(-12.65,-8.25,5.3,4.2).has_point(p): return "西の機器室"
	if p.y > 6: return "出口A" if p.x<0 else "出口B"
	return "西の中庭" if p.x<0 else "東の中庭"

func _request_decision(observer: Dictionary,trigger: String,location: Vector2,candidates: Array) -> void:
	if observer.hp<=0: return
	# Strong evidence takes priority over a newer weak sound.
	if tactical_assist and trigger=="noise" and _team_has_visual_contact(observer): return
	if not tactical_assist: revision+=1
	var urgent: bool=trigger in ["contact","objective_missing"]
	if (pending and not urgent) or (not urgent and time-last_decision_time<1.0):
		if queued_decision.is_empty() or trigger!="noise" or queued_decision.trigger=="noise":
			queued_decision={"observer":observer,"trigger":trigger,"location":location,"candidates":candidates}
		return
	if tactical_assist:
		revision+=1
		if urgent: queued_decision.clear()
	last_decision_time=time
	request_id+=1
	var sent_revision:=revision
	var sent_run:=run_id
	var selected_mode:=mode
	var local_choice:=_baseline(observer,trigger,candidates)
	var available_team: Array=Tactics.team(self,observer)
	if available_team.size()<2 and "paired_inspection" in candidates:
		candidates=candidates.duplicate()
		candidates.erase("paired_inspection")
	# Counter-watch needs a concrete observed alternate location to execute.
	# Both modes receive this same physical feasibility constraint.
	if "counter_watch" in candidates and (available_team.size()<2 or Tactics.alternate(self,observer,location)==Vector2.INF):
		candidates=candidates.duplicate()
		candidates.erase("counter_watch")
		local_choice=_baseline(observer,trigger,candidates)
	local_choice=_baseline(observer,trigger,candidates)
	var forecasts: Array=Tactics.forecast(self,observer,location,candidates)
	# Action projections remain an inspection aid. Live ablation found that adding
	# them to Jev's observations over-selected paired checks on harmless sounds.
	var selected_observations: Array=Tactics.observations(self,observer,trigger,location)
	last_baseline=CHOICE_NAMES.get(local_choice,local_choice)
	var evidence_snapshot: String=Tactics.evidence_text(self,observer)
	var baseline_forecast: String=Tactics.forecast_text(forecasts,local_choice)
	last_evidence=evidence_snapshot
	var controlled_comparison: bool=replay.comparing and not tactical_assist
	if tactical_assist or (mode=="rules" and not controlled_comparison):
		last_forecast=Tactics.forecast_text(forecasts,local_choice)
		decision_source="ルール"
		decision_name=CHOICE_NAMES[local_choice]
		trace.append({"time":time,"trigger":trigger,"choice":local_choice,"baseline":local_choice,"source":"rules","latency_ms":0,"observations":selected_observations,"evidence_text":evidence_snapshot,"forecast_text":last_forecast,"baseline_forecast_text":baseline_forecast})
		trace.back()["observer"]=observer.id
		trace.back()["candidates"]=candidates.duplicate()
		trace.back()["phase"]="baseline"
		_apply_decision(local_choice,observer,location)
		if mode=="rules": return
	pending=true
	pending_age=0
	var request:=HTTPRequest.new()
	request.timeout=4.0
	add_child(request)
	var sent_at_ms := Time.get_ticks_msec()
	var sent_game_time := time
	var timing: Dictionary={"response_ms":0 if selected_mode=="rules" else -1}
	var sent_request_id: int=request_id
	var payload: Dictionary={"request_id":"run%d-%d"%[run_id,request_id],"revision":sent_revision,"trigger":trigger,"observations":selected_observations,"mission":"Protect the case and prevent escape. Support current visual contact. Keep a sentry. Use witnessed event sequences to weigh diversions; never assume an unseen intruder position.","candidates":candidates,"mode":selected_mode}
	var handle_response: Callable=func(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
		request.queue_free()
		if run_id!=sent_run: return
		if sent_request_id==request_id: pending=false
		if sent_revision!=revision or observer.hp<=0 or finished or (trigger=="noise" and time-observer.seen_at<4) or (tactical_assist and trigger!="contact" and _team_has_visual_contact(observer)):
			_log("状況が変わったため古い判断を破棄")
			return
		var decoded:=JSON.new()
		var response: Variant=decoded.data if decoded.parse(body.get_string_from_utf8())==OK else null
		var valid: bool=result==HTTPRequest.RESULT_SUCCESS and code==200 and response is Dictionary and response.get("choice","") in candidates and response.get("revision",-1)==sent_revision and response.get("request_id","")==payload.request_id and response.get("source","") in ["jev","rules","fallback"]
		var response_ms: int=int(timing.response_ms) if int(timing.response_ms)>=0 else Time.get_ticks_msec()-sent_at_ms
		var choice: String=local_choice
		if valid:
			choice=response.choice
			last_confidence=float(response.get("confidence",0.0)) if response.get("confidence")!=null else 0.0
			var source: String=response.get("source","fallback")
			if source=="fallback": choice=local_choice
			decision_source="Jev" if source=="jev" else ("ルール" if source=="rules" else "代替ルール")
			if source=="jev":
				api_calls+=1
				api_tokens+=int(response.get("input_tokens",0))
				service_status="Jev往復 · %d ms"%response_ms
			else:
				service_status={"missing_api_key":"キー未取得：代替ルールで動作","demo_disabled":"Jev停止中：代替ルールで動作","rate_or_budget_limited":"利用上限：代替ルールで動作","api_unavailable_or_invalid":"応答失敗：代替ルールで動作","rules_mode":"ルールモード"}.get(response.get("status",""),"代替ルールで動作")
		else:
			decision_source="代替ルール"
			service_status="比較の期限超過・応答失敗：代替ルール" if controlled_comparison else "API未接続・応答失敗：通常AIで継続"
		if controlled_comparison: service_status+=" / 判断適用は両方式1.5秒後"
		decision_name=CHOICE_NAMES[choice]
		last_baseline=CHOICE_NAMES.get(local_choice,local_choice)
		last_evidence=evidence_snapshot
		last_forecast=Tactics.forecast_text(forecasts,choice)
		trace.append({"time":time,"trigger":trigger,"choice":choice,"baseline":local_choice,"source":decision_source,"latency_ms":response_ms,"comparison_wait":COMPARISON_WAIT if controlled_comparison else 0.0,"application_delay":time-sent_game_time,"observations":selected_observations,"raw_choice":response.get("raw_choice",choice) if valid else choice,"diversion_probability":response.get("diversion_probability") if valid else null,"evidence_text":evidence_snapshot,"forecast_text":last_forecast,"baseline_forecast_text":baseline_forecast})
		trace.back()["observer"]=observer.id
		trace.back()["candidates"]=candidates.duplicate()
		trace.back()["phase"]="assist" if tactical_assist else "decision"
		trace.back()["changed"]=choice!=local_choice
		if not tactical_assist or choice!=local_choice:
			_apply_decision(choice,observer,location)
		else:
			_record_assignments(observer)
		if history.panel.visible: history.refresh(self)
		_log(observer.id+"："+decision_name+"  ["+decision_source+"]")
	if controlled_comparison:
		var ticket: int=comparison_gate.schedule(time+COMPARISON_WAIT,handle_response,func():
			if is_instance_valid(request): request.queue_free()
		)
		if selected_mode=="rules":
			var local_response: Dictionary={"choice":local_choice,"source":"rules","status":"rules_mode","request_id":payload.request_id,"revision":sent_revision}
			comparison_gate.receive(ticket,[HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(local_response).to_utf8_buffer()])
			return
		request.request_completed.connect(func(result:int,code:int,headers:PackedStringArray,body:PackedByteArray):
			if comparison_gate.receive(ticket,[result,code,headers,body]):
				timing.response_ms=Time.get_ticks_msec()-sent_at_ms
		)
	else:
		request.request_completed.connect(func(result:int,code:int,headers:PackedStringArray,body:PackedByteArray):
			timing.response_ms=Time.get_ticks_msec()-sent_at_ms
			handle_response.call(result,code,headers,body)
		)
	var err:=request.request(service_url+"/decision",["Content-Type: application/json","User-Agent: RELAY-StealthDemo/5.1"],HTTPClient.METHOD_POST,JSON.stringify(payload))
	if err==OK: api_sent+=1
	if err!=OK:
		# A failed send in the controlled replay waits for the same deadline too.
		if controlled_comparison: return
		request.queue_free()
		pending=false
		decision_source="代替ルール"
		decision_name=CHOICE_NAMES[local_choice]
		last_forecast=baseline_forecast
		service_status="送信失敗：通常AIで継続"
		trace.append({"time":time,"trigger":trigger,"choice":local_choice,"baseline":local_choice,"source":decision_source,"latency_ms":0,"observations":selected_observations,"evidence_text":evidence_snapshot,"forecast_text":baseline_forecast,"baseline_forecast_text":baseline_forecast})
		trace.back()["observer"]=observer.id
		trace.back()["candidates"]=candidates.duplicate()
		if not tactical_assist: _apply_decision(local_choice,observer,location)
		else: _record_assignments(observer)

func _baseline(g: Dictionary,trigger: String,candidates: Array) -> String:
	return Tactics.baseline(self,g,trigger,candidates)

func _record_assignments(observer: Dictionary) -> void:
	if trace.is_empty(): return
	var assignments: Array=[]
	for guard: Dictionary in Tactics.team(self,observer):
		assignments.append({"id":guard.id,"role":guard.role,"place":_place(guard.target),"target":guard.target})
	trace.back()["assignments"]=assignments
	if explanation.is_open(): explanation.refresh(self,trace.back())

func _apply_decision(choice: String,observer: Dictionary,location: Vector2) -> void:
	var before: Dictionary={}
	for guard: Dictionary in guards:
		before[guard.id]={"role":guard.role,"target":guard.target}
	Tactics.apply(self,choice,observer,location)
	if trace.is_empty() or trace.back().get("choice","")!=choice or not is_equal_approx(float(trace.back().time),time): return
	_record_assignments(observer)
	var changes: Array=[]
	for guard: Dictionary in guards:
		if guard.hp>0 and (guard.role!=before[guard.id].role or guard.target.distance_to(before[guard.id].target)>1):
			changes.append({"id":guard.id,"role":ROLE_NAMES.get(guard.role,guard.role),"place":_place(guard.target)})
	feedback.decision(self,trace.back(),changes)
	if guided_comparison and replay.comparing and trace.size()==3 and not guided_pauses.has(mode):
		guided_pauses[mode]=true
		explanation.show_panel(self,trace.back())
	elif explanation.is_open():
		explanation.refresh(self,trace.back())

func start_guided_comparison() -> void:
	if explanation.is_open(): explanation.close(self)
	if history.panel.visible: history.close(self)
	paused=false
	guided_pauses.clear()
	guided_comparison=true
	replay.variant=0
	replay.start_comparison(self)

func plan_markers_refresh() -> void:
	for marker in plan_nodes:
		if is_instance_valid(marker): marker.queue_free()
	plan_nodes.clear()
	for guard: Dictionary in guards:
		if guard.hp<=0: continue
		var color:=Color("ecbb72")
		var marker: MeshInstance3D=level.make_ring(color,0.65)
		add_child(marker)
		marker.position=_v3(guard.target,0.14)
		plan_nodes.append(marker)

func _update_plan_lines() -> void:
	plan_mesh.clear_surfaces()
	for marker in plan_nodes:
		if is_instance_valid(marker): marker.visible=false
	var lines: Array=[]
	var i:=0
	for guard: Dictionary in guards:
		if guard.hp<=0: continue
		if i<plan_nodes.size() and is_instance_valid(plan_nodes[i]):
			plan_nodes[i].position=_v3(guard.target,0.14)
			plan_nodes[i].visible=inspect_enabled and guard.role!="patrol"
		if inspect_enabled and guard.role!="patrol" and guard.pos.distance_to(guard.target)>0.7:
			var points: PackedVector2Array=nav.get_point_path(_nearest_open(_cell(guard.pos)),_nearest_open(_cell(guard.target)))
			var color:=Color("e3b66f")
			for j in range(0,points.size()-1,2): lines.append([points[j],points[j+1],color])
		i+=1
	if not lines.is_empty():
		plan_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for line: Array in lines:
			plan_mesh.surface_set_color(line[2])
			plan_mesh.surface_add_vertex(_v3(line[0],0.18))
			plan_mesh.surface_set_color(line[2])
			plan_mesh.surface_add_vertex(_v3(line[1],0.18))
		plan_mesh.surface_end()

func _check_service() -> void:
	var request:=HTTPRequest.new()
	request.timeout=4
	var health_request_count:=api_sent
	add_child(request)
	request.request_completed.connect(func(_result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
		request.queue_free()
		# A startup health reply must not replace a newer real decision status.
		if api_sent!=health_request_count: return
		var decoded:=JSON.new()
		var response: Variant=decoded.data if decoded.parse(body.get_string_from_utf8())==OK else null
		if code==200 and response is Dictionary and response.get("service","")=="jev-stealth-demo":
			service_status="Jev待機中" if response.get("api_key_configured",false) else "キー未取得：代替ルールで動作"
			if not response.get("enabled",true): service_status="Jev停止中：代替ルールで動作"
		else: service_status="接続確認できず：次の判断で再接続"
		_update_ui()
	)
	request.request(service_url+"/health",["User-Agent: RELAY-StealthDemo/5.1"])

func _v3(p: Vector2,height:=0.0) -> Vector3:
	return Vector3(p.x,height,p.y)

func _log(text: String) -> void:
	event_log.append(text)
	if event_log.size()>5: event_log.pop_front()

func _finish(won: bool) -> void:
	if finished: return
	success=won and player_hp>0
	finished=true
	damage_flash=0.0
	revision+=1
	result_label.add_theme_font_size_override("font_size",20)
	result_label.text=feedback.debrief(self,success)
	feedback_panel.hide()
	result_panel.show()
	_update_ui()

func _build_ui() -> void:
	Briefing.build(self)

func _label(parent: Node,text: String,pos: Vector2,size: int) -> Label:
	var label:=Label.new()
	label.text=text
	label.position=pos
	label.add_theme_font_size_override("font_size",size)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _panel(parent: Node,pos: Vector2,size: Vector2) -> PanelContainer:
	var panel:=PanelContainer.new()
	panel.position=pos
	panel.custom_minimum_size=size
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.035,0.065,0.085,0.93)
	style.border_color=Color(0.2,0.37,0.40,0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left=20
	style.content_margin_right=20
	style.content_margin_top=16
	style.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	return panel

func _update_ui() -> void:
	Briefing.update(self)

func _qa_tick(delta: float) -> void:
	qa_clock+=delta
	if qa_phase==0 and qa_clock>1:
		qa_phase=1
		_noise(Vector2(-8,-1),"Heard a metallic impact in the west courtyard")
	elif qa_phase==1 and qa_clock>3:
		qa_phase=2
		_capture("initial")
	elif qa_phase==2 and qa_clock>6:
		qa_phase=3
		player_pos=Vector2(9,-4)
		_apply_decision("flank_and_cover",guards[2],player_pos)
		was_detected=true
	elif qa_phase==3 and qa_clock>8:
		qa_phase=4
		_capture("combat")
	elif qa_phase==4 and qa_clock>9:
		qa_phase=5
		player_pos=CASE_POS+Vector2(0,0.7)
		_interact()
		assert(has_case)
		player_pos=EXITS[0]
	elif qa_phase==5 and qa_clock>11:
		get_tree().quit()

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	var err:=get_viewport().get_texture().get_image().save_png("res://captures/"+name+".png")
	print("QA_CAPTURE ",name," ",err)
