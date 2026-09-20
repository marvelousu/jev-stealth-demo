extends RefCounted
## Comparison commands go through ordinary sensing/actions; no decision is forced.
var invulnerable := true
var recording := false
var playing := false
var comparing := false
var samples: Array = []
var actions: Array = []
var last_sample := -1.0
var cursor := 0
var action_cursor := 0
var clock := 0.0
var phase := 0
var stage := 0
var comparison_results: Array = []
var route: PackedVector2Array = []
var route_index := 0
var crossing_smoke := false
var late_smoke := false
var exit_reached_at := -1.0
var variant := 0
var report_at := -1.0
var allows_objective_interactions := false
const VARIANTS := ["反復音＋銃声9秒", "反復音だけ", "単発音＋銃声9秒", "反復音＋銃声11秒", "反復音＋銃声13秒"]
const REPORT_TIMES := [9.0, 9.0, 9.0, 11.0, 13.0]

func condition_label() -> String:
	return VARIANTS[variant]

func change_variant(game) -> void:
	if comparing or playing: return
	variant=(variant+1)%VARIANTS.size()
	game.comparison_label.text="F8で比較："+VARIANTS[variant]+"　F9で条件切替（観察用・無敵）"

func end_observation(game, message: String) -> void:
	game.comparison_gate.clear()
	game.revision+=1
	game.pending=false
	game.queued_decision.clear()
	game.active=false
	game.result_label.text="観察用リプレイ終了\n\n"+message+"\n\nここでは任務の成功・生存率を判定していません。\nR：新しい実戦を開始　F8：もう一度観察"
	game.result_panel.show()

func stop() -> void:
	recording=false;playing=false;comparing=false
	Input.action_release("crouch")

func toggle_record(game) -> void:
	if comparing or playing: return
	recording=not recording
	if recording:
		game._reset();game.active=true;game.intro.hide()
		samples.clear();actions.clear();last_sample=-1
	game.comparison_label.text="記録中：普段どおり潜入してください。F6で終了" if recording else "経路を記録しました。Mで方式を選び、F7で同じ経路を再生"

func event(game, kind: String) -> void:
	if recording:
		actions.append({"time":game.time,"kind":kind,"aim":game.aim_pos})

func play_recording(game) -> void:
	if samples.is_empty() or recording: return
	comparing=false;playing=true;clock=0;cursor=0;action_cursor=0
	game._reset();game.active=true;game.intro.hide()
	game.comparison_label.text="記録経路を再生："+game.mode+"（比較用：被弾で中断しません）"

func start_comparison(game) -> void:
	recording=false;playing=false;comparing=true;phase=0;clock=0;stage=0
	comparison_results.clear()
	begin_phase(game)

func begin_phase(game) -> void:
	game._reset();game.active=true;game.intro.hide()
	game.mode="rules" if phase==0 else "jev"
	Input.action_press("crouch")
	clock=0;stage=0
	crossing_smoke=false
	late_smoke=false
	exit_reached_at=-1.0
	route=game.nav.get_point_path(game._cell(game.player_pos),game._cell(Vector2(12,8)))
	route.append_array(game.nav.get_point_path(game._cell(Vector2(12,8)),game._cell(Vector2(12,5))))
	route_index=0
	game.comparison_label.text="観察比較・両方式1.5秒後に判断を適用 %d/2：%s｜%s"%[phase+1,"ルール" if phase==0 else "Jev",VARIANTS[variant]]

func tick(game,delta: float) -> void:
	if recording and game.time-last_sample>=0.1:
		last_sample=game.time
		samples.append({"time":game.time,"pos":game.player_pos,"aim":game.aim_pos,"crouch":Input.is_action_pressed("crouch"),"has_case":game.has_case})
	if playing:
		clock+=delta;game.player_hp=100
		while cursor+1<samples.size() and samples[cursor+1].time<=clock: cursor+=1
		game.player_pos=samples[cursor].pos;game.aim_pos=samples[cursor].aim
		game.has_case=bool(samples[cursor].get("has_case",false))
		game.level.case_visual.visible=not game.has_case
		if samples[cursor].get("crouch",false): Input.action_press("crouch")
		else: Input.action_release("crouch")
		while action_cursor<actions.size() and actions[action_cursor].time<=clock:
			var action: Dictionary=actions[action_cursor];game.aim_pos=action.aim
			execute(game,action.kind);action_cursor+=1
		if clock>samples.back().time+3:
			playing=false;Input.action_release("crouch");game.comparison_label.text="記録再生が終了しました："+game.mode
			end_observation(game,"被弾相当 %d　発見 %d回"%[int(game.damage_taken),game.detected_count])
	if not comparing: return
	clock+=delta;game.player_hp=100
	if stage==0:
		game.aim_pos=Vector2(-7,1);game._throw_noise(variant!=2);stage=1
	if clock>2 and clock<14 and route_index<route.size():
		if game.player_pos.distance_to(route[route_index])<0.3: route_index+=1
		if route_index<route.size(): game.player_pos=game._move(game.player_pos,(route[route_index]-game.player_pos).limit_length(2.7*delta))
	if stage==1 and clock>(report_at if report_at>=0 else REPORT_TIMES[variant]):
		if variant!=1:
			game.aim_pos=Vector2(8,0);game._shoot_player()
		stage=2
	if not crossing_smoke and clock>6.3:
		game.aim_pos=game.player_pos;game._throw_smoke();crossing_smoke=true
	if not late_smoke and clock>11:
		# Smoke timing stays identical when only gunfire timing changes.
		game.aim_pos=game.player_pos;game._throw_smoke();late_smoke=true
	if clock>26:
		# Finish the same route past the eastern gate to measure actual perception,
		# rather than declaring success solely from different role labels.
		game.player_pos=game._move(game.player_pos,(game.EXITS[1]-game.player_pos).limit_length(2.7*delta))
		if exit_reached_at<0 and game.player_pos.distance_to(game.EXITS[1])<1.35: exit_reached_at=game.time
	if clock>32:
		var observed_exit := false
		var before_exit := false
		for guard: Dictionary in game.guards:
			for event: Dictionary in guard.events:
				if event.time>=16 and event.point.distance_to(game.EXITS[1])<8 and event.fact.begins_with("Saw an armed intruder"):
					observed_exit=true
					if exit_reached_at>=0 and event.time<exit_reached_at: before_exit=true
		comparison_results.append({"mode":game.mode,"variant":VARIANTS[variant],"damage_equivalent":game.damage_taken,"first_damage_at":game.first_damage_at,"lethal_damage_at":game.lethal_damage_at,"detections":game.detected_count,"decisions":game.trace.duplicate(true),"guards":positions(game),"exit_route_observed":observed_exit,"observed_before_exit":before_exit,"exit_reached_at":exit_reached_at})
		if phase==0:
			phase=1;begin_phase(game)
		else:
			comparing=false
			Input.action_release("crouch")
			game.comparison_label.text="比較結果｜ルール：%s / Jev：%s　Rで自由に再挑戦"%["出口の手前で発見" if comparison_results[0].observed_before_exit else "出口の手前では未発見","出口の手前で発見" if comparison_results[1].observed_before_exit else "出口の手前では未発見"]
			var file:=FileAccess.open("user://last-comparison.json",FileAccess.WRITE)
			file.store_string(JSON.stringify(comparison_results,"\t"))
			file.close()
			var adopted:=0
			var fallback:=0
			for entry: Dictionary in comparison_results[1].decisions:
				if entry.source=="Jev": adopted+=1
				else: fallback+=1
			end_observation(game,"%s\n致死量相当：ルール %s / Jev設定 %s\nJev採用 %d件・代替 %d件\nF9：音・銃声の間隔を変える"%[VARIANTS[variant],lethal_text(comparison_results[0]),lethal_text(comparison_results[1]),adopted,fallback])

func execute(game,kind: String) -> void:
	match kind:
		"noise": game._throw_noise()
		"noise_single": game._throw_noise(false)
		"smoke": game._throw_smoke()
		"interact": game._interact()
		"shot": game._shoot_player()

func positions(game) -> Array:
	var result: Array=[]
	for guard: Dictionary in game.guards:
		result.append({"id":guard.id,"role":guard.role,"position":[guard.pos.x,guard.pos.y],"target":[guard.target.x,guard.target.y],"observations":guard.events.duplicate(true)})
	return result

func lethal_text(result: Dictionary) -> String:
	return "%.1f秒"%float(result.lethal_damage_at) if float(result.lethal_damage_at)>=0 else "到達せず"
