extends RefCounted
## Factual mission-event recording and compact debrief presentation.

const MAX_EVENTS := 64
const MAX_DEBRIEF_EVENTS := 4
const MAX_EVENT_CHARS := 32
const CHOICE_NAMES := {
	"inspect": "一人で確認",
	"paired_inspection": "確認役と援護役",
	"hold_position": "持ち場を維持",
	"sweep_last_known": "最後に見た場所を捜索",
	"contain_exits": "出口の封鎖",
	"flank_and_cover": "追跡・側面・援護",
	"counter_watch": "囮を警戒・別経路へ先回り",
}

var events: Array = []
var notice: String = ""
var notice_until: float = 0.0


func reset() -> void:
	events.clear()
	notice = ""
	notice_until = 0.0


func record(game, kind: String, text: String, details: Dictionary = {}) -> void:
	var item: Dictionary = {
		"time": float(game.time),
		"kind": kind,
		"text": text,
	}
	var copied_details: Dictionary = details.duplicate(true)
	for key in copied_details:
		item[key] = copied_details[key]
	events.append(item)
	while events.size() > MAX_EVENTS:
		events.pop_front()


func decision(game, entry: Dictionary, changes: Array) -> void:
	if changes.is_empty():
		return
	var source := _source_name(str(entry.get("source", "")))
	var choice := str(entry.get("choice", ""))
	var change_lines: Array[String] = []
	for change in changes:
		if not change is Dictionary:
			continue
		var change_dict: Dictionary = change
		var guard_id := str(change_dict.get("id", "?"))
		var role := str(change_dict.get("role", ""))
		var place := str(change_dict.get("place", ""))
		change_lines.append("%s %s・%s" % [guard_id, role, place])
		if change_lines.size() >= 2:
			break
	if change_lines.is_empty():
		return

	var change_text := " / ".join(change_lines)
	var decision_text := "%s：%s／%s" % [source, _choice_name(choice), change_text]
	var evidence_text := str(entry.get("evidence_text", ""))
	record(game, "decision", decision_text, {
		"choice": choice,
		"baseline": str(entry.get("baseline", "")),
		"source": source,
		"evidence_text": evidence_text,
		"changes": changes.duplicate(true),
	})
	notice = "敵の対応 [%s]：%s\n%s" % [source, _choice_name(choice), change_text]
	notice_until = float(game.time) + 4.0


func latest_notice(game) -> String:
	if notice.is_empty() or float(game.time) >= notice_until:
		notice = ""
		return ""
	return notice


func debrief(game, won: bool) -> String:
	var lines: Array[String] = []
	var outcome := "任務成功" if won else "任務失敗"
	lines.append("%s　経過 %.1f秒" % [outcome, float(game.time)])
	lines.append("ケース：%s　／　耐久：%d / 100" % ["確保" if bool(game.has_case) else "未回収", int(maxf(0.0, float(game.player_hp)))])
	lines.append("今回の経過")

	var selected_indices: Array[int] = []
	var latest_decision := -1
	var latest_contact := -1
	var latest_hit := -1
	var latest_pickup := -1
	for index in range(events.size()):
		var event: Dictionary = events[index]
		var kind := str(event.get("kind", ""))
		if kind == "decision":
			var choice := str(event.get("choice", ""))
			var baseline := str(event.get("baseline", ""))
			if not baseline.is_empty() and choice != baseline:
				latest_decision = index
		if kind == "contact" or str(event.get("trigger", "")) == "contact":
			latest_contact = index
		if kind in ["damage", "hit", "player_hit"] or kind.begins_with("damage"):
			latest_hit = index
		if kind in ["pickup", "casepickup"]:
			latest_pickup = index

	_append_unique(selected_indices, latest_decision)
	_append_unique(selected_indices, latest_contact)
	_append_unique(selected_indices, latest_hit)
	_append_unique(selected_indices, latest_pickup)
	if selected_indices.size() < MAX_DEBRIEF_EVENTS:
		for index in range(events.size() - 1, -1, -1):
			var event: Dictionary = events[index]
			if _is_noise_or_smoke(str(event.get("kind", ""))):
				continue
			_append_unique(selected_indices, index)
			if selected_indices.size() >= MAX_DEBRIEF_EVENTS:
				break
	selected_indices.sort()

	if selected_indices.is_empty():
		lines.append("記録された経過はありません。")
	else:
		for index in selected_indices:
			lines.append(_event_line(events[index]))

	lines.append("次に試すこと")
	lines.append(_next_hint(game, won, latest_hit))
	lines.append("H：判断履歴　／　R：再挑戦　／　M：方式切替")
	while lines.size() > 14:
		lines.remove_at(lines.size() - 2)
	return "\n".join(lines)


func _append_unique(indices: Array[int], index: int) -> void:
	if index >= 0 and index not in indices:
		indices.append(index)


func _event_line(event: Dictionary) -> String:
	var event_time := float(event.get("time", 0.0))
	var text := str(event.get("text", event.get("kind", "")))
	return _truncate("%.1f秒：%s" % [event_time, text], MAX_EVENT_CHARS)


func _next_hint(game, won: bool, latest_hit: int) -> String:
	if won:
		return "Mで判断方式を切り替え、Rで同じ任務へ再挑戦できます。"
	if latest_hit >= 0 and int(game.smoke_charges) > 0:
		return "赤い照準線が出たらGで煙幕を使えます。"
	if bool(game.has_case):
		return "ケース携行中は減速します。遮蔽物を使い、出口でEを長押しします。"
	return "Shiftでしゃがみ、遮蔽物を使って進みます。"


func _choice_name(choice: String) -> String:
	return str(CHOICE_NAMES.get(choice, choice if not choice.is_empty() else "未記録"))


func _source_name(source: String) -> String:
	match source.to_lower():
		"rules":
			return "ルール"
		"jev":
			return "Jev"
		"fallback":
			return "代替ルール"
		"代替ルール":
			return "代替ルール"
	return source if not source.is_empty() else "記録なし"


func _is_noise_or_smoke(kind: String) -> bool:
	var normalized := kind.to_lower()
	return normalized in ["noise", "smoke", "initialq", "fnoise", "smoke1", "smoke2"] or normalized.contains("noise") or normalized.contains("smoke")


func _truncate(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, max(1, limit - 1)) + "…"
