extends "res://main.gd"
## Alternate playable layout: long approaches on both sides of central cover.
## All perception, tactical choices and enemy movement use the existing code.
var courtyard_ready := false
var finish_delay := 0.0

func _ready() -> void:
	tactical_assist=true
	super._ready()
	var old_cover: Array[String]=["Central_Blast_Cover","East_Crates","West_Barrier","South_Cable_Cover","South_East_Barrier"]
	for label: String in old_cover:
		var solid=level.get_node("Solid_"+label)
		level.remove_child(solid)
		solid.queue_free()
	# The last five rectangles belong to those same five cover objects.
	level.obstacles.resize(level.obstacles.size()-5)
	level._add_obstacle(Rect2(-3.5,-2.5,7,7),1.1,Color("#3d4c54"),"Courtyard Central Building")
	_build_nav()
	courtyard_ready=true
	replay=load("res://courtyard_replay.gd").new()
	if "--play" in OS.get_cmdline_user_args():
		_reset()
		replay.invulnerable=false
		active=false
		intro.show()
	else:
		replay.start_comparison(self)

func _reset() -> void:
	super._reset()
	finish_delay=0.0
	if not courtyard_ready: return
	player_pos=Vector2(-11,8)
	player.position=_v3(player_pos)
	var starts: Array[Vector2]=[Vector2(-7,4),Vector2(6,6),Vector2(10,-3)]
	for i in range(guards.size()):
		var g: Dictionary=guards[i]
		g.pos=starts[i]
		g.target=starts[i]
		g.patrol=[[Vector2(-7,4),Vector2(-11,6),Vector2(-6,-2),Vector2(-5,4)],[Vector2(6,6),Vector2(-4,6),Vector2(6,4),Vector2(10,1)],[Vector2(10,-3),Vector2(7,0),Vector2(11,3),Vector2(10,-5)]][i]
		g.last_seen=starts[i]
		g.face=[Vector2(-1,1).normalized(),Vector2.LEFT,Vector2.DOWN][i]
		g.node.position=_v3(starts[i])
		g.path.clear()

func _physics_process(delta: float) -> void:
	if finished and replay.playing:
		replay.stop()
		return
	if finished and replay.comparing:
		finish_delay+=delta
		if finish_delay>=0.7: replay.finish_phase(self)
		return
	super._physics_process(delta)

func _update_ui() -> void:
	super._update_ui()
	if courtyard_ready and replay.comparing:
		comparison_label.text="通常の耐久・発見・攻撃判定で比較\n%s：%s"%["通常AI＋Jev" if mode=="jev" else "通常AI","ケースを持って出口へ" if has_case else "保管庫のケースを回収する"]
