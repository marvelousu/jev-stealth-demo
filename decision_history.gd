extends RefCounted
## Modal view for the decisions recorded during the current run.

const PANEL_POSITION := Vector2(310, 185)
const PANEL_SIZE := Vector2(760, 535)
const MAX_ENTRIES := 20
const CHOICE_NAMES := {
	"inspect": "一人で確認",
	"paired_inspection": "確認役と援護役",
	"hold_position": "持ち場を維持",
	"sweep_last_known": "最後に見た場所を捜索",
	"contain_exits": "出口の封鎖",
	"flank_and_cover": "追跡・側面・援護",
	"counter_watch": "囮を警戒・別経路へ先回り",
}

var panel: PanelContainer
var body: VBoxContainer
var game
var _scroll: ScrollContainer
var _footer: Label


func build(owner) -> void:
	game = owner
	if is_instance_valid(panel):
		panel.queue_free()
	panel = null
	body = null
	_scroll = null
	_footer = null

	panel = PanelContainer.new()
	panel.name = "DecisionHistoryPanel"
	panel.position = PANEL_POSITION
	panel.size = PANEL_SIZE
	panel.custom_minimum_size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.z_index = 40
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.065, 0.085, 0.98)
	panel_style.border_color = Color(0.35, 0.72, 0.72, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 22
	panel_style.content_margin_right = 22
	panel_style.content_margin_top = 18
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	owner.ui_root.add_child(panel)

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_theme_constant_override("separation", 9)
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 38)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(header)
	var title := Label.new()
	title.text = "今回の判断履歴"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("71e4cb"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる [H / Esc]"
	close_button.custom_minimum_size = Vector2(190, 36)
	close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.pressed.connect(func() -> void: close(owner))
	header.add_child(close_button)

	var note := Label.new()
	note.text = "敵の観測と実際の選択。ルール欄はこの時点だけの比較で、勝敗予測ではありません。"
	note.add_theme_font_size_override("font_size", 16)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(0, 27)
	note.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(note)

	_scroll = ScrollContainer.new()
	_scroll.name = "DecisionHistoryScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 360)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_scroll)

	body = VBoxContainer.new()
	body.name = "DecisionHistoryEntries"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.add_child(body)

	_footer = Label.new()
	_footer.text = "出所：Jev / ルール / 代替ルール（通信失敗時の継続判断）"
	_footer.add_theme_font_size_override("font_size", 15)
	_footer.add_theme_color_override("font_color", Color("a6c9c9"))
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.custom_minimum_size = Vector2(0, 27)
	_footer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_footer)

	panel.hide()


func toggle(owner) -> void:
	if not is_instance_valid(panel):
		build(owner)
	game = owner
	if panel.visible:
		close(owner)
		return
	refresh(owner)
	panel.show()
	owner.paused = true
	if is_instance_valid(owner.pause_label):
		owner.pause_label.hide()


func close(owner) -> void:
	game = owner
	if is_instance_valid(panel):
		panel.hide()
	owner.paused = false
	if is_instance_valid(owner.pause_label):
		owner.pause_label.hide()


func refresh(owner) -> void:
	game = owner
	if not is_instance_valid(panel):
		build(owner)
		return
	for child in body.get_children():
		child.queue_free()
	var trace: Array = owner.trace if owner.trace is Array else []
	if trace.is_empty():
		var empty := Label.new()
		empty.text = "まだ判断履歴はありません。"
		empty.add_theme_font_size_override("font_size", 20)
		empty.add_theme_color_override("font_color", Color("b7cece"))
		empty.custom_minimum_size = Vector2(0, 48)
		empty.mouse_filter = Control.MOUSE_FILTER_STOP
		body.add_child(empty)
		return

	var first_index: int = max(0, trace.size() - MAX_ENTRIES)
	for index in range(trace.size() - 1, first_index - 1, -1):
		var entry: Dictionary = trace[index] if trace[index] is Dictionary else {}
		_add_card(owner, entry)
		if index > first_index:
			var separator := HSeparator.new()
			separator.custom_minimum_size = Vector2(0, 2)
			separator.mouse_filter = Control.MOUSE_FILTER_STOP
			body.add_child(separator)


func _add_card(owner, entry: Dictionary) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.065, 0.12, 0.135, 0.96)
	card_style.border_color = Color(0.2, 0.42, 0.45, 0.9)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(5)
	card_style.content_margin_left = 13
	card_style.content_margin_right = 13
	card_style.content_margin_top = 9
	card_style.content_margin_bottom = 9
	card.add_theme_stylebox_override("panel", card_style)
	body.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_child(content)

	var choice: String = str(entry.get("choice", ""))
	var source: String = str(entry.get("source", "記録なし"))
	var source_text: String = _source_name(source)
	var time_text: String = _format_time(entry.get("time", ""))
	var headline := Label.new()
	headline.text = "%s秒  %s：%s" % [time_text, source_text, _choice_name(choice)]
	headline.add_theme_font_size_override("font_size", 19)
	headline.add_theme_color_override("font_color", Color("e2f2ee"))
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(headline)

	var baseline: String = str(entry.get("baseline", ""))
	var baseline_text: String = _choice_name(baseline) if not baseline.is_empty() else "未記録"
	if not baseline.is_empty() and baseline == choice:
		baseline_text += "（同じ選択）"
	var baseline_label := Label.new()
	baseline_label.text = "同じ観測のルール: " + baseline_text
	baseline_label.add_theme_font_size_override("font_size", 18)
	baseline_label.add_theme_color_override("font_color", Color("f0c674"))
	baseline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	baseline_label.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(baseline_label)

	var evidence_text: String = str(entry.get("evidence_text", ""))
	var evidence_label := Label.new()
	evidence_label.text = "要求時の直近の観測：" + (evidence_text if not evidence_text.is_empty() else "未記録")
	evidence_label.add_theme_font_size_override("font_size", 17)
	evidence_label.add_theme_color_override("font_color", Color("c4d7d4"))
	evidence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	evidence_label.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(evidence_label)

	var forecast_text: String = str(entry.get("forecast_text", ""))
	if not forecast_text.is_empty():
		_add_text(content, "要求時点の配置見込み：" + forecast_text, Color("a8e3d8"))
	if not baseline.is_empty() and baseline != choice:
		var baseline_forecast: String = str(entry.get("baseline_forecast_text", ""))
		if not baseline_forecast.is_empty():
			_add_text(content, "ルールの見込み：" + baseline_forecast, Color("e4ca8a"))

	if source.to_lower() in ["jev", "fallback"] or source == "代替ルール":
		var latency_value: Variant = entry.get("latency_ms", null)
		if latency_value != null:
			_add_text(content, "往復時間：%d ms" % int(latency_value), Color("9fb7b7"))
	if float(entry.get("comparison_wait",0))>0:
		_add_text(content, "観察比較：両方式とも要求から1.5秒後に適用", Color("9fb7b7"))


func _add_text(parent: VBoxContainer, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(label)


func _choice_name(choice: String) -> String:
	return str(CHOICE_NAMES.get(choice, choice if not choice.is_empty() else "未記録"))


func _source_name(source: String) -> String:
	match source.to_lower():
		"jev":
			return "Jev"
		"fallback":
			return "代替ルール"
		"rules":
			return "ルール"
	return source if not source.is_empty() else "記録なし"


func _format_time(value: Variant) -> String:
	if value is int or value is float:
		return "%.1f" % float(value)
	return str(value) if not str(value).is_empty() else "—"
