extends RefCounted
## Explains one recorded team decision without inventing a current game state.

const PANEL_POSITION := Vector2(70, 90)
const PANEL_SIZE := Vector2(1300, 700)
const MAIN_FONT_SIZE := 20
const SECONDARY_FONT_SIZE := 17
const SMALL_FONT_SIZE := 15

var panel: PanelContainer
var title_label: Label
var input_label: Label
var choice_label: Label
var assignments_label: Label
var note_label: Label

var _subtitle_label: Label
var _candidate_label: Label
var _evidence_label: Label
var _record_meta_label: Label
var _previous_paused := false
var _paused_owner


func build(owner) -> void:
	if is_instance_valid(panel):
		return
	if not is_instance_valid(owner) or not is_instance_valid(owner.ui_root):
		return

	panel = PanelContainer.new()
	panel.name = "DecisionExplanationPanel"
	panel.position = PANEL_POSITION
	panel.size = PANEL_SIZE
	panel.custom_minimum_size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.z_index = 50
	panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.018, 0.038, 0.050, 1.0), Color(0.33, 0.72, 0.73, 0.95), 2, 9, 22
	))
	owner.ui_root.add_child(panel)

	var root := VBoxContainer.new()
	root.name = "ExplanationContent"
	root.add_theme_constant_override("separation", 8)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 34)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(header)
	title_label = Label.new()
	title_label.text = "判断の解説"
	title_label.add_theme_font_size_override("font_size", 27)
	title_label.add_theme_color_override("font_color", Color("71e4cb"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	header.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "動きを見る / 閉じる [F1・Esc]"
	close_button.custom_minimum_size = Vector2(285, 36)
	close_button.add_theme_font_size_override("font_size", 17)
	close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.pressed.connect(func() -> void: close(owner))
	header.add_child(close_button)

	_subtitle_label = Label.new()
	_subtitle_label.text = "このデモでは、Jevが部隊の戦術を選び、ゲーム側のコードがA/B/Cの担当と行き先へ変換します。"
	_subtitle_label.add_theme_font_size_override("font_size", SECONDARY_FONT_SIZE)
	_subtitle_label.add_theme_color_override("font_color", Color("b9d9d5"))
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.custom_minimum_size = Vector2(0, 30)
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_subtitle_label)

	var columns := HBoxContainer.new()
	columns.name = "ExplanationColumns"
	columns.add_theme_constant_override("separation", 12)
	columns.custom_minimum_size = Vector2(0, 286)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(columns)

	var input_column := _column("① ゲームが記録")
	columns.add_child(input_column)
	input_label = _body_label()
	input_label.custom_minimum_size = Vector2(0, 100)
	input_column.get_child(0).add_child(input_label)
	_record_meta_label = _body_label()
	_record_meta_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_record_meta_label.add_theme_color_override("font_color", Color("a7c4c1"))
	_record_meta_label.custom_minimum_size = Vector2(0, 30)
	input_column.get_child(0).add_child(_spacer(4))
	input_column.get_child(0).add_child(_label_heading("観測者・記録"))
	input_column.get_child(0).add_child(_record_meta_label)

	var choice_column := _column("② Jevまたはルールが選択")
	columns.add_child(choice_column)
	choice_label = _body_label()
	choice_label.custom_minimum_size = Vector2(0, 100)
	choice_column.get_child(0).add_child(choice_label)
	_candidate_label = _body_label()
	_candidate_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_candidate_label.add_theme_color_override("font_color", Color("a7c4c1"))
	_candidate_label.custom_minimum_size = Vector2(0, 80)
	choice_column.get_child(0).add_child(_spacer(4))
	choice_column.get_child(0).add_child(_label_heading("候補"))
	choice_column.get_child(0).add_child(_candidate_label)

	var assignment_column := _column("③ ゲームが割り当て")
	columns.add_child(assignment_column)
	assignments_label = _body_label()
	assignments_label.custom_minimum_size = Vector2(0, 150)
	assignment_column.get_child(0).add_child(assignments_label)

	var evidence_row := VBoxContainer.new()
	evidence_row.add_theme_constant_override("separation", 3)
	evidence_row.custom_minimum_size = Vector2(0, 75)
	evidence_row.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(evidence_row)
	evidence_row.add_child(_label_heading("要求時点の直近3行の事実"))
	_evidence_label = _body_label()
	_evidence_label.add_theme_font_size_override("font_size", SECONDARY_FONT_SIZE)
	_evidence_label.custom_minimum_size = Vector2(0, 43)
	evidence_row.add_child(_evidence_label)

	note_label = Label.new()
	note_label.text = "従来AIも過去を記憶し、同じ行動を実装できます。今回は固定ルールと戦術の選び方を比較しています。\n記憶はゲーム側が保持。音声は送らず、A/B/CそれぞれにJevを常駐させる構成でもありません。\n狙い：出来事の組み合わせに応じた判断を作りやすくすること。その効果は、この1例だけでは証明できません。"
	note_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	note_label.add_theme_color_override("font_color", Color("b9d0cc"))
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.custom_minimum_size = Vector2(0, 48)
	note_label.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(note_label)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size = Vector2(0, 38)
	footer.add_theme_constant_override("separation", 10)
	footer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(footer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var compare_button := Button.new()
	compare_button.text = "解説付き比較を開始 [F10]"
	compare_button.custom_minimum_size = Vector2(285, 38)
	compare_button.add_theme_font_size_override("font_size", 17)
	compare_button.mouse_filter = Control.MOUSE_FILTER_STOP
	compare_button.pressed.connect(func() -> void:
		if is_instance_valid(owner):
			owner.start_guided_comparison()
	)
	footer.add_child(compare_button)

	panel.hide()
	close_button.call_deferred("grab_focus")


func show_panel(owner, entry: Dictionary = {}) -> void:
	if not is_instance_valid(panel):
		build(owner)
	if not is_instance_valid(panel):
		return
	if not is_open():
		_previous_paused = bool(owner.paused)
		_paused_owner = owner
	refresh(owner, entry)
	panel.show()
	owner.paused = true
	if is_instance_valid(owner.pause_label):
		owner.pause_label.hide()


func toggle(owner) -> void:
	if is_open():
		close(owner)
	else:
		show_panel(owner)


func close(owner) -> void:
	if is_instance_valid(panel):
		panel.hide()
	var restore_owner = _paused_owner if is_instance_valid(_paused_owner) else owner
	if is_instance_valid(restore_owner):
		restore_owner.paused = _previous_paused
		if is_instance_valid(restore_owner.pause_label):
			restore_owner.pause_label.visible = _previous_paused
	_paused_owner = null


func is_open() -> bool:
	return is_instance_valid(panel) and panel.visible


func refresh(owner, entry: Dictionary = {}) -> void:
	if not is_instance_valid(panel):
		build(owner)
	if not is_instance_valid(panel):
		return
	var actual := _latest_entry(owner, entry)
	if actual.is_empty():
		_show_empty()
		return

	var observer := str(actual.get("observer", ""))
	var evidence := _three_lines(str(actual.get("evidence_text", "")))
	var choice := str(actual.get("choice", ""))
	var baseline := str(actual.get("baseline", ""))
	var source := str(actual.get("source", ""))
	var selected_name := _choice_name(owner, choice)
	var baseline_name := _choice_name(owner, baseline)

	# Keep this column bounded to the Japanese three-line evidence snapshot. The
	# raw observations payload can contain verbose service dictionaries and is
	# intentionally not rendered in this compact explanation view.
	input_label.text = "観測された入力\n" + (evidence if not evidence.is_empty() else "未記録")
	_record_meta_label.text = "記録者：" + (observer if not observer.is_empty() else "ゲーム")
	choice_label.text = "採用戦術：" + selected_name + "\n出所：" + _source_name(source) + "\n同じ観測のルール：" + baseline_name
	_candidate_label.text = _candidates_text(owner, actual.get("candidates", []), choice)
	if actual.get("diversion_probability")!=null:
		_candidate_label.text+="\n\nJevの補助判定：出来事の関連 %.0f%%"%(float(actual.diversion_probability)*100)
	assignments_label.text = _assignments_text(owner, actual.get("assignments", []))
	_evidence_label.text = evidence if not evidence.is_empty() else "未記録"
	var time_value: String = _time_text(actual.get("time", ""))
	if not time_value.is_empty():
		_record_meta_label.text += "　時刻：" + time_value


func _show_empty() -> void:
	input_label.text = "ゲーム側の担当\n音や視界を検出し、出来事を記憶。\n選んだ履歴をJevへ渡します。\n\n今回の観測記録：未記録"
	_record_meta_label.text = "記録者：未記録"
	choice_label.text = "Jevの担当\n候補から部隊の戦術を1つ選択。\n移動先や経路は生成しません。\n\n今回の採用戦術：未記録"
	_candidate_label.text = "用意する候補の例：一人で確認、援護、別経路も警戒。\n実際に提示した候補：未記録"
	assignments_label.text = "ゲーム側の担当\n戦術をA/B/Cの役割と行き先へ変換。\n移動・照準・射撃を実行します。\n\n今回の割り当て：未記録"
	_evidence_label.text = "未記録"


func _latest_entry(owner, entry: Dictionary) -> Dictionary:
	if not entry.is_empty():
		return entry
	if not is_instance_valid(owner) or not owner.trace is Array:
		return {}
	for index in range(owner.trace.size() - 1, -1, -1):
		if owner.trace[index] is Dictionary and not owner.trace[index].is_empty():
			return owner.trace[index]
	return {}


func _observations_text(observations: Variant) -> String:
	if observations is Array and not observations.is_empty():
		var lines: Array[String] = []
		for observation in observations:
			var line := str(observation).strip_edges()
			if not line.is_empty():
				lines.append("・" + line)
		if not lines.is_empty():
			return "\n".join(lines.slice(0, 4))
	var text := str(observations).strip_edges()
	return text if not text.is_empty() and text != "[]" else "未記録"


func _candidates_text(owner, candidates: Variant, selected: String) -> String:
	if not candidates is Array or candidates.is_empty():
		return "他の候補（未選択）：未記録"
	var names: Array[String] = []
	for candidate in candidates:
		var id := str(candidate)
		if id.is_empty() or id == selected:
			continue
		names.append(_choice_name(owner, id))
		if names.size() >= 7:
			break
	return "他の候補（未選択）：" + ("、".join(names) if not names.is_empty() else "なし")


func _assignments_text(owner, assignments: Variant) -> String:
	if not assignments is Array or assignments.is_empty():
		return "コードが割り当てた担当（採用時）\n未記録"
	var lines: Array[String] = ["コードが割り当てた担当（採用時）"]
	for assignment in assignments:
		if not assignment is Dictionary:
			continue
		var id := str(assignment.get("id", "?"))
		var role := str(assignment.get("role", ""))
		var role_name := _role_name(owner, role)
		var place := str(assignment.get("place", ""))
		if place.is_empty() and assignment.has("target"):
			place = _vector_text(assignment.get("target"))
		var line := "%s：%s" % [id, role_name if not role_name.is_empty() else "担当未記録"]
		if not place.is_empty():
			line += "　" + place
		lines.append(line)
		if lines.size() >= 6:
			break
	return "\n".join(lines) if lines.size() > 1 else "コードが割り当てた担当（採用時）\n未記録"


func _choice_name(owner, choice: String) -> String:
	if choice.is_empty():
		return "未記録"
	if is_instance_valid(owner) and owner.CHOICE_NAMES is Dictionary:
		return str(owner.CHOICE_NAMES.get(choice, choice))
	return choice


func _role_name(owner, role: String) -> String:
	if role.is_empty():
		return ""
	if is_instance_valid(owner) and owner.ROLE_NAMES is Dictionary:
		return str(owner.ROLE_NAMES.get(role, role))
	return role


func _source_name(source: String) -> String:
	match source.to_lower():
		"jev":
			return "Jev"
		"rules":
			return "ルール"
		"fallback":
			return "代替ルール"
		"代替ルール":
			return "代替ルール"
		"":
			return "未記録"
	return source


func _three_lines(text: String) -> String:
	if text.is_empty():
		return ""
	var lines := text.split("\n", false)
	var kept: Array[String] = []
	for line in lines:
		var clean := str(line).strip_edges()
		if not clean.is_empty():
			kept.append(clean)
		if kept.size() >= 3:
			break
	return "\n".join(kept)


func _time_text(value: Variant) -> String:
	if value is int or value is float:
		return "%.1f秒" % float(value)
	var text := str(value).strip_edges()
	return text


func _vector_text(value: Variant) -> String:
	if value is Vector2:
		return "(%.1f, %.1f)" % [value.x, value.y]
	return str(value) if value != null else ""


func _column(heading: String) -> PanelContainer:
	var column := PanelContainer.new()
	column.custom_minimum_size = Vector2(0, 286)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_theme_stylebox_override("panel", _panel_style(
		Color(0.045, 0.090, 0.102, 1.0), Color(0.17, 0.38, 0.40, 0.9), 1, 6, 14
	))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(body)
	body.add_child(_label_heading(heading))
	return column


func _label_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", MAIN_FONT_SIZE)
	label.add_theme_color_override("font_color", Color("e6f4ef"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	return label


func _body_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", SECONDARY_FONT_SIZE)
	label.add_theme_color_override("font_color", Color("d5e6e2"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	return label


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _panel_style(background: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = 13
	style.content_margin_bottom = 12
	return style
