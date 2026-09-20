extends RefCounted
## Shared briefing and HUD layout. Gameplay owns state; this module only presents it.

const VIEW_SIZE := Vector2(1440, 900)
const HEADER_WIDTH := 1020.0
const PANEL_X := 1080.0
const PANEL_WIDTH := 330.0
const LOG_WIDTH := 350.0

static func build(game) -> void:
	var layer := CanvasLayer.new()
	game.add_child(layer)
	game.ui_root = Control.new()
	game.ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui_root.custom_minimum_size = VIEW_SIZE
	game.ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(game.ui_root)

	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Noto Sans CJK JP"])
	theme.default_font = font
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", Color("dfebe9"))
	game.ui_root.theme = theme

	var header := Control.new()
	header.position = Vector2(30, 20)
	header.size = Vector2(HEADER_WIDTH, 115)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.ui_root.add_child(header)
	game.headline = game._label(header, "RELAY / ENEMY INTELLIGENCE", Vector2.ZERO, 26)
	game.headline.add_theme_color_override("font_color", Color("71e4cb"))
	game.objective = game._label(header, "1 北東のケースを回収 [E長押し]  →  2 南の出口A/Bで離脱 [E長押し]", Vector2(0, 42), 20)
	game.objective.custom_minimum_size = Vector2(HEADER_WIDTH, 30)
	game.health_bar = ProgressBar.new()
	game.health_bar.position = Vector2(0, 80)
	game.health_bar.size = Vector2(360, 22)
	game.health_bar.min_value = 0
	game.health_bar.max_value = 100
	game.health_bar.value = 100
	game.health_bar.show_percentage = false
	var health_background := StyleBoxFlat.new()
	health_background.bg_color = Color(0.08, 0.14, 0.16, 0.95)
	health_background.set_corner_radius_all(5)
	game.health_bar.add_theme_stylebox_override("background", health_background)
	var health_fill := StyleBoxFlat.new()
	health_fill.bg_color = Color("71e4cb")
	health_fill.set_corner_radius_all(5)
	game.health_bar.add_theme_stylebox_override("fill", health_fill)
	header.add_child(game.health_bar)
	game.vitals = game._label(header, "耐久 100", Vector2(380, 78), 17)
	game.vitals.custom_minimum_size = Vector2(620, 28)

	game.interaction_bar = ProgressBar.new()
	game.interaction_bar.position = Vector2(30, 145)
	game.interaction_bar.size = Vector2(560, 25)
	game.interaction_bar.min_value = 0
	game.interaction_bar.max_value = 1.2
	game.interaction_bar.value = 0
	game.interaction_bar.show_percentage = false
	game.interaction_bar.visible = false
	game.ui_root.add_child(game.interaction_bar)
	game.threat_label = game._label(game.ui_root, "脅威：低", Vector2(610, 143), 18)
	game.threat_label.custom_minimum_size = Vector2(390, 30)
	game.threat_label.add_theme_color_override("font_color", Color("f0c674"))

	game.detail_panel = _fixed_panel(game, Vector2(PANEL_X, 25), Vector2(PANEL_WIDTH, 360))
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 7)
	game.detail_panel.add_child(detail_box)
	game._label(detail_box, "仕組み [F1] / 履歴 [H]", Vector2.ZERO, 18)
	game.ai_label = game._label(detail_box, "", Vector2.ZERO, 15)
	game.ai_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.ai_label.custom_minimum_size = Vector2(285, 215)

	var log_panel := _fixed_panel(game, Vector2(PANEL_X, 410), Vector2(LOG_WIDTH, 300))
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.log_label = game._label(log_panel, "", Vector2.ZERO, 15)
	game.log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.log_label.custom_minimum_size = Vector2(305, 260)

	game.comparison_label = game._label(game.ui_root, "実戦・体力0で失敗　／　F9 条件切替", Vector2(30, 748), 21)
	game.comparison_label.custom_minimum_size = Vector2(1020, 34)
	game.comparison_label.add_theme_color_override("font_color", Color("9bd9ef"))
	game.prompt_label = game._label(game.ui_root, "", Vector2(30, 712), 18)
	game.prompt_label.custom_minimum_size = Vector2(1020, 34)
	var legend: Label = game._label(game.ui_root, "WASD 移動   Shift しゃがむ   マウス 照準 / 左クリック 射撃\nE 長押し：ケース / 出口   E：電源切替   Q 単発物音   F 反復物音   G 煙幕   M 方式切替   R 再挑戦   F8 観察   F9 条件切替   F6 記録   F7 再生   H 判断履歴   Esc 一時停止", Vector2(30, 823), 15)
	legend.custom_minimum_size = Vector2(1020, 54)

	game.pause_label = game._label(game.ui_root, "PAUSED / Escで再開", Vector2(580, 410), 26)
	game.pause_label.hide()
	game.music_button=Button.new()
	game.music_button.position=Vector2(1140,750)
	game.music_button.size=Vector2(270,40)
	game.music_button.text="BGM：ON [B]"
	game.music_button.pressed.connect(game._toggle_music)
	game.ui_root.add_child(game.music_button)

	game.damage_overlay = ColorRect.new()
	game.damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.damage_overlay.color = Color(0.82, 0.03, 0.02, 0.0)
	game.damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.damage_overlay.z_index = 20
	game.ui_root.add_child(game.damage_overlay)

	game.intro = _fixed_panel(game, Vector2(280, 135), Vector2(840, 635))
	var intro_style: StyleBoxFlat=game.intro.get_theme_stylebox("panel").duplicate()
	intro_style.bg_color=Color("09131b")
	game.intro.add_theme_stylebox_override("panel",intro_style)
	var intro_box := VBoxContainer.new()
	intro_box.add_theme_constant_override("separation", 10)
	game.intro.add_child(intro_box)
	game._label(intro_box, "RELAY", Vector2.ZERO, 38)
	game._label(intro_box, "Jevに任せるのは、部隊の戦術を選ぶ部分", Vector2.ZERO, 24)
	var boundary: Label=game._label(intro_box,"ゲームが観測・記憶 → Jevが戦術を選択 → コードがA/B/Cへ割当\n移動・視界・射撃は共通。従来AIも過去の情報を使えます。",Vector2.ZERO,19)
	boundary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	boundary.custom_minimum_size=Vector2(780,55)
	var instructions: Label = game._label(intro_box, "1) 北東のケースへ入り、Eを1.2秒長押し\n2) ケース携行中は移動速度が下がります\n3) 南の出口A/BでEを2.5秒長押し\n4) 3発の被弾で致命的。赤い照準線は射撃警告、遮蔽物と煙幕で射線を切れます\n\n弾薬 6　物音 3　煙幕 2\nQ：単発の物音。F：反復物音は設置時・8秒後・16秒後に鳴る。G：煙は5秒。北西の電源を切ると遠距離の無線連携が途切れます。", Vector2.ZERO, 17)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.custom_minimum_size = Vector2(780,220)
	var start_button := Button.new()
	start_button.text = "任務を開始"
	start_button.custom_minimum_size = Vector2(0, 42)
	start_button.pressed.connect(func() -> void:
		game.active = true
		game.intro.hide()
	)
	intro_box.add_child(start_button)
	var compare_button := Button.new()
	compare_button.text = "解説付き比較：入力 → 選択 → 割り当てを見る [F10]"
	compare_button.custom_minimum_size = Vector2(0, 42)
	compare_button.pressed.connect(func() -> void:
		game.start_guided_comparison()
	)
	intro_box.add_child(compare_button)
	var explain_button:=Button.new()
	explain_button.text="Jevとゲーム側の担当を確認 [F1]"
	explain_button.custom_minimum_size=Vector2(0,38)
	explain_button.pressed.connect(func():game.explanation.show_panel(game))
	intro_box.add_child(explain_button)

	game.result_panel = _fixed_panel(game, Vector2(400, 220), Vector2(640, 440))
	game.result_label = game._label(game.result_panel, "", Vector2.ZERO, 23)
	game.result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.result_panel.hide()

	game.feedback_panel = _fixed_panel(game,Vector2(340,188),Vector2(650,76))
	game.feedback_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	game.feedback_label=game._label(game.feedback_panel,"",Vector2.ZERO,17)
	game.feedback_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	game.feedback_label.custom_minimum_size=Vector2(600,42)
	game.feedback_panel.hide()

static func update(game) -> void:
	if not is_instance_valid(game.objective):
		return

	var carrying := bool(game.has_case)
	game.objective.text = "1 回収済み ✓  →  2 南出口でE2.5秒（運搬で減速）" if carrying else "1 北東のケースを回収 [E長押し 1.2秒]  →  2 南の出口A/Bで離脱 [E長押し 2.5秒]"
	game.health_bar.value = clampf(float(game.player_hp), 0.0, 100.0)
	var health_fill: StyleBoxFlat = game.health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if health_fill != null:
		health_fill.bg_color = Color("f06a67") if float(game.player_hp) <= 33.0 else Color("71e4cb")
	var ammo_value: int = int(game.ammo)
	game.vitals.text = "耐久 %d　弾薬 %d　物音 %d　煙幕 %d　中継電源 %s" % [int(maxf(0.0, float(game.player_hp))), ammo_value, int(game.noise_charges), int(game.smoke_charges), "ON" if game.power_on else "OFF"]

	var interaction_kind: String = str(game.interaction_kind)
	var interaction_progress: float = float(game.interaction_progress)
	var interaction_limit: float = 1.0
	if interaction_kind == "pickup":
		interaction_limit = 1.2
	elif interaction_kind == "extract":
		interaction_limit = 2.5
	game.interaction_bar.max_value = interaction_limit
	game.interaction_bar.value = clampf(interaction_progress, 0.0, interaction_limit)
	game.interaction_bar.visible = not interaction_kind.is_empty() or interaction_progress > 0.0

	var replay_active := bool(game.replay.comparing or game.replay.playing)
	var variant_pattern: String = game.replay.condition_label()
	var mode_text: String = "ルール" if game.mode == "rules" else "Jev"
	var damage_equivalent: int = int(game.damage_taken)
	if game.replay.recording:
		game.comparison_label.text = "記録中：普段どおり潜入してください。F6で停止"
		game.comparison_label.add_theme_color_override("font_color", Color("8fe8ff"))
	elif replay_active and game.tactical_assist:
		game.comparison_label.text = "通常の耐久・回収・脱出判定で"+("比較" if game.replay.comparing else "記録を再生")+"\n"+mode_text+"　／　条件："+variant_pattern
		game.comparison_label.add_theme_color_override("font_color", Color("8fe8ff"))
	elif replay_active:
		var timing_note: String="／判断適用は両方式1.5秒後" if game.replay.comparing else "／記録経路の再生"
		game.comparison_label.text = "観察用・被弾無効／任務判定なし"+timing_note+"\n%s　／　条件：%s　／　被ダメージ相当：%d" % [mode_text, variant_pattern, damage_equivalent]
		game.comparison_label.add_theme_color_override("font_color", Color("8fe8ff"))
	elif bool(game.replay.recording):
		game.comparison_label.text = "記録中：F6で停止　／　F7で現在方式の経路を再生\nF8の条件："+variant_pattern
		game.comparison_label.add_theme_color_override("font_color", Color("f3d37a"))
	elif game.finished:
		game.comparison_label.text="実戦終了："+("離脱成功" if game.success else "任務失敗")+"　／　Hで判断履歴・Rで再挑戦"
		game.comparison_label.add_theme_color_override("font_color", Color("9bd9ef"))
	elif not game.active and game.result_panel.visible:
		game.comparison_label.text = "観察終了・Rで新しい実戦　／　F9 条件切替\n選択中："+variant_pattern
		game.comparison_label.add_theme_color_override("font_color", Color("8fe8ff"))
	else:
		game.comparison_label.text = "実戦・体力0で失敗　／　F8 比較・F9 条件切替\n選択中："+variant_pattern
		game.comparison_label.add_theme_color_override("font_color", Color("9bd9ef"))

	if replay_active and not game.tactical_assist and game.lethal_damage_at>=0:
		game.comparison_label.text = "観察用・被弾無効／任務判定なし："+("Jev" if game.mode=="jev" else "ルール")+("／両方式1.5秒待機" if game.replay.comparing else "")+"\n実戦なら %.1f 秒で戦闘不能（記録経路の被ダメージから算出）"%game.lethal_damage_at
	game.prompt_label.text = "" if game.finished else _context_hint(game, carrying, interaction_kind, interaction_progress, interaction_limit)
	if game.finished: game.interaction_bar.hide()
	game.threat_label.text = _threat_text(game)
	var notice: String=game.feedback.latest_notice(game)
	game.feedback_label.text=notice
	game.feedback_panel.visible=not notice.is_empty() and game.active and not game.finished and not game.paused and not game.intro.visible and not replay_active
	game.ai_label.text = _decision_text(game)
	var assignments: PackedStringArray=[]
	if not game.trace.is_empty():
		for assignment: Dictionary in game.trace.back().get("assignments",[]):
			assignments.append(assignment.id+"："+str(game.ROLE_NAMES.get(assignment.role,assignment.role))+" → "+assignment.place)
	game.log_label.text="③ ゲーム側が割り当て（採用時）\n"+("\n".join(assignments) if not assignments.is_empty() else "まだ割り当ての記録はありません")+"\n\n移動・射撃は通常のゲームAIが実行\n\nF1：入力から実行までを確認\nF10：解説付き比較"
	var damage_flash: float = clampf(float(game.damage_flash), 0.0, 0.55)
	game.damage_overlay.color = Color(0.82, 0.03, 0.02, damage_flash)

static func _fixed_panel(game, position: Vector2, size: Vector2) -> PanelContainer:
	var panel: PanelContainer = game._panel(game.ui_root, position, size)
	panel.size = size
	panel.custom_minimum_size = size
	return panel

static func _context_hint(game, carrying: bool, interaction_kind: String, progress: float, limit: float) -> String:
	if interaction_kind == "pickup":
		return "E長押し：ケースを回収　%.1f / %.1f 秒" % [progress, limit]
	if interaction_kind == "extract":
		return "E長押し：この出口から離脱　%.1f / %.1f 秒" % [progress, limit]
	if not carrying and game.player_pos.distance_to(game.CASE_POS) < 1.8:
		return "ケースへもう少し近づく（回収はE長押し1.2秒）"
	for exit_pos: Vector2 in game.EXITS:
		if carrying and game.player_pos.distance_to(exit_pos) < 1.8:
			return "出口の中心へもう少し近づく（離脱はE長押し2.5秒）"
	if game.player_pos.distance_to(game.POWER_POS) < 2.0:
		return "E：中継電源を切替"
	return ""

static func _threat_text(game) -> String:
	var threat_score := 0.0
	var active_guards := 0
	for guard: Dictionary in game.guards:
		if float(guard.get("hp", 0.0)) <= 0.0:
			continue
		var fire: float = float(guard.get("fire", 0.0))
		var detect: float = clampf(float(guard.get("detect", 0.0)), 0.0, 1.0)
		var recent_seen: bool = game.time - float(guard.get("direct_seen_at", -100.0)) < 1.0
		var guard_score: float = maxf(detect * 0.7, 0.0)
		if fire > 0.0:
			guard_score = maxf(guard_score, 0.8)
		if recent_seen:
			guard_score = maxf(guard_score, 1.0)
		if guard_score > 0.0:
			active_guards += 1
			threat_score += guard_score
	if active_guards == 0:
		return "脅威：低　／　現在の射線外"
	if threat_score >= 2.0:
		return "脅威：高　／　%d名が警戒・射撃" % active_guards
	return "脅威：中　／　%d名の警戒" % active_guards

static func _decision_text(game) -> String:
	var mode_text := "Jev" if game.mode == "jev" else "ルール"
	var tactic_text := "判断中（通常行動は継続）" if game.pending else str(game.decision_name)
	var evidence: String = str(game.last_evidence)
	if evidence.is_empty():
		evidence = "まだ観測事実はありません"
	var baseline_text: String = str(game.last_baseline)
	if baseline_text.is_empty():
		baseline_text = "不明"
	var api_text: String = "ローカル判断（通信なし）" if game.mode == "rules" else "%s\n送信 %d回／Jev採用 %d回" % [str(game.service_status), int(game.api_sent), int(game.api_calls)]
	return "① ゲーム側が観測・記憶\n%s\n\n② 戦術を選ぶ担当：%s\n採用元：%s\n選択：%s\n同じ観測のルール：%s\n\n%s" % [evidence,mode_text,str(game.decision_source),tactic_text,baseline_text,api_text]
