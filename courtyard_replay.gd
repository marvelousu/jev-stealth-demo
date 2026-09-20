extends "res://replay.gd"
## Courtyard comparison, recording and playback share ordinary mission rules.
var scenario := "loop"
var objective_stage := 0
var near_case_smoke := false
var fired := false
var second_noise := false

const SCENARIO_LABELS := {
	"loop": "迂回・煙幕・再度の物音",
	"rush": "直進",
	"crouch": "しゃがみで直進",
	"diversion": "物音で陽動",
	"break_contact": "煙幕で接触を切る",
	"double_back": "引き返して保管庫へ",
}

func condition_label() -> String:
	return str(SCENARIO_LABELS.get(scenario, scenario))

func begin_phase(game) -> void:
	invulnerable=false
	game._reset()
	game.active=true
	game.intro.hide()
	game.mode="rules" if phase==0 else "jev"
	allows_objective_interactions=true
	_release_synthetic_input()
	clock=0
	stage=0
	objective_stage=0
	crossing_smoke=false
	near_case_smoke=false
	fired=false
	second_noise=false
	set_route(game,[Vector2(6,6),Vector2(6,-3),Vector2(-5,-3),Vector2(-6,5),Vector2(12,7),game.CASE_POS] if scenario=="loop" else [Vector2(12,8),game.CASE_POS])
	if scenario=="crouch": Input.action_press("crouch")
	game.comparison_label.text="通常の耐久で比較："+game.mode

func set_route(game,waypoints: Array) -> void:
	route.clear()
	route_index=0
	var from: Vector2=game.player_pos
	for destination: Vector2 in waypoints:
		var segment: PackedVector2Array=game.nav.get_point_path(game._nearest_open(game._cell(from)),game._nearest_open(game._cell(destination)))
		if segment.is_empty():
			push_error("Replay route has an unreachable waypoint")
			game.replay.comparing=false
			return
		route.append_array(segment)
		from=destination

func follow_route(game,delta: float) -> bool:
	if route_index<route.size() and game.player_pos.distance_to(route[route_index])<0.22: route_index+=1
	if route_index<route.size():
		game.player_pos=game._move(game.player_pos,(route[route_index]-game.player_pos).limit_length(game.movement_speed(scenario=="crouch")*delta))
		return false
	return true

func toggle_record(game) -> void:
	if comparing or playing: return
	if recording:
		_record_sample(game)
		recording=false
		_release_synthetic_input()
		game.comparison_label.text="経路を記録しました。Mで方式を選び、F7で同じ経路を通常耐久で再生"
		return
	_release_synthetic_input()
	recording=true
	invulnerable=false
	allows_objective_interactions=true
	comparison_results.clear()
	game._reset()
	game.active=true
	game.intro.hide()
	samples.clear()
	actions.clear()
	last_sample=-1
	_record_sample(game)
	game.comparison_label.text="記録中：普段どおり潜入してください。F6で停止"

func play_recording(game) -> void:
	if samples.is_empty() or recording: return
	_release_synthetic_input()
	comparing=false
	playing=true
	invulnerable=false
	allows_objective_interactions=true
	comparison_results.clear()
	clock=0
	cursor=0
	action_cursor=0
	game._reset()
	game.active=true
	game.intro.hide()
	game.comparison_label.text="記録経路を再生："+game.mode+"（通常の耐久・任務判定）"

func stop() -> void:
	recording=false
	playing=false
	comparing=false
	allows_objective_interactions=false
	_release_synthetic_input()

func _record_sample(game) -> void:
	last_sample=game.time
	samples.append({"time":game.time,"pos":game.player_pos,"aim":game.aim_pos,"crouch":Input.is_action_pressed("crouch"),"interact":Input.is_action_pressed("interact")})

func _release_synthetic_input() -> void:
	Input.action_release("crouch")
	Input.action_release("interact")

func _set_playback_input(sample: Dictionary) -> void:
	if bool(sample.get("crouch",false)): Input.action_press("crouch")
	else: Input.action_release("crouch")
	if bool(sample.get("interact",false)): Input.action_press("interact")
	else: Input.action_release("interact")

func _tick_recording(game) -> void:
	if game.time-last_sample>=0.1: _record_sample(game)

func _tick_playback(game,delta: float) -> void:
	clock+=delta
	while cursor+1<samples.size() and float(samples[cursor+1].time)<=clock: cursor+=1
	var sample: Dictionary=samples[cursor]
	game.player_pos=sample.pos
	game.player.position=game._v3(game.player_pos)
	game.aim_pos=sample.aim
	_set_playback_input(sample)
	while action_cursor<actions.size() and float(actions[action_cursor].time)<=clock:
		var action: Dictionary=actions[action_cursor]
		game.aim_pos=action.aim
		execute(game,action.kind)
		action_cursor+=1
	if clock>float(samples.back().time)+3:
		playing=false
		_release_synthetic_input()
		end_observation(game,"記録経路を最後まで再生しました。")

func tick(game,delta: float) -> void:
	if recording:
		_tick_recording(game)
		return
	if playing:
		_tick_playback(game,delta)
		return
	if not comparing: return
	clock+=delta
	if stage==0:
		if scenario not in ["rush","crouch"]:
			game.aim_pos=Vector2(-10,0)
			game._throw_noise(true)
		stage=1
	if scenario in ["break_contact","double_back","loop"]:
		if not crossing_smoke and clock>1.4:
			game.aim_pos=game.player_pos+Vector2(3,0)
			game._throw_smoke()
			crossing_smoke=true
		if not fired and clock>7:
			game.aim_pos=Vector2(14,8)
			game._shoot_player()
			fired=true
		if not near_case_smoke and clock>(5.2 if scenario=="loop" else 6.0):
			game.aim_pos=game.player_pos+Vector2(0,-5)
			game._throw_smoke()
			near_case_smoke=true
	if scenario=="loop" and clock>11.0 and not second_noise:
		game.aim_pos=Vector2(-4.5,-2)
		game._throw_noise(true)
		second_noise=true
	if scenario=="double_back" and clock>6 and not second_noise:
		set_route(game,[Vector2(5,6),Vector2(5,-3),Vector2(10,-3),game.CASE_POS])
		second_noise=true
	if objective_stage==0:
		if follow_route(game,delta): objective_stage=1
	elif objective_stage==1:
		Input.action_press("interact")
		if game.has_case:
			Input.action_release("interact")
			objective_stage=2
			set_route(game,[game.EXITS[1]])
	elif objective_stage==2:
		if follow_route(game,delta): objective_stage=3
	elif objective_stage==3:
		Input.action_press("interact")
	if clock>50: finish_phase(game)

func _mission_line(result: Dictionary) -> String:
	var outcome := "離脱成功" if bool(result.get("success",false)) else "任務失敗"
	var case_text := "回収" if bool(result.get("has_case",false)) else "未回収"
	return "%s　ケース%s　耐久%d　%.1f秒" % [outcome,case_text,int(maxf(0.0,float(result.get("hp",0.0)))),float(result.get("duration",0.0))]

func end_observation(game, message: String) -> void:
	game.comparison_gate.clear()
	game.revision+=1
	game.pending=false
	game.queued_decision.clear()
	game.active=false
	_release_synthetic_input()
	if comparison_results.size()>=2:
		game.result_label.text="通常耐久の比較終了\n\n条件："+condition_label()+"\n通常AI："+_mission_line(comparison_results[0])+"\n通常AI＋Jev："+_mission_line(comparison_results[1])+"\n\n"+message+"\n\nR：通常プレイ　F8：再比較"
	else:
		var replay_result := {"success":game.success,"has_case":game.has_case,"hp":game.player_hp,"duration":game.time}
		game.result_label.text="記録経路の再生終了\n\n"+_mission_line(replay_result)+"\n\n"+message+"\n\nR：通常プレイ　F8：比較"
	game.result_panel.show()

func finish_phase(game) -> void:
	if not comparing: return
	_release_synthetic_input()
	comparison_results.append({"mode":game.mode,"scenario":scenario,"decisions":game.trace.duplicate(true),"guards":positions(game),"detections":game.detected_count,"damage_equivalent":game.damage_taken,"hp":game.player_hp,"has_case":game.has_case,"success":game.success,"duration":game.time,"objective_stage":objective_stage,"objective_events":game.feedback.events.duplicate(true)})
	if phase==0:
		phase=1
		begin_phase(game)
	else:
		comparing=false
		end_observation(game,"通常AIと通常AI＋Jevを、同じ条件の通常耐久で比較しました。")

func change_variant(game) -> void:
	if comparing or playing: return
	var names: Array=["loop","rush","crouch","diversion","break_contact","double_back"]
	scenario=names[(names.find(scenario)+1)%names.size()]
	game.comparison_label.text="F8で通常耐久の比較："+condition_label()+"　F9で条件切替"
