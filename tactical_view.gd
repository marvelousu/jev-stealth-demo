extends Control
## Observation-only readable view of actual game state. Never supplies Jev inputs.
var game
var font: Font
func _ready() -> void:
	position=Vector2(90,180)
	size=Vector2(970,525)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	z_index=5
	font=get_theme_default_font()
func _process(_delta: float) -> void:
	visible=game.guided_comparison and game.replay.comparing and not game.intro.visible
	if visible: queue_redraw()
func at(point: Vector2) -> Vector2:
	return Vector2(22+(point.x+15)*30.8,30+(point.y+10)*23.4)
func words(point: Vector2,content: String,color: Color=Color("182938"),font_size: int=19) -> void:
	draw_string(font,point,content,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
func _draw() -> void:
	if game==null: return
	draw_rect(Rect2(Vector2.ZERO,size),Color("e8eef0"))
	words(Vector2(25,22),"実際の位置・担当を見やすく表示　青▲＝あなた　橙●＝敵",Color("213849"),19)
	for obstacle: Rect2 in game.level.obstacles:
		draw_rect(Rect2(at(obstacle.position),obstacle.size*Vector2(30.8,23.4)),Color("7b8a95"))
	for exit_pos: Vector2 in game.EXITS:
		draw_rect(Rect2(at(exit_pos)-Vector2(22,12),Vector2(44,24)),Color("9abf9f"))
	draw_rect(Rect2(at(game.CASE_POS)-Vector2(9,6),Vector2(18,12)),Color("b18b1e"))
	for device: Dictionary in game.devices:
		var p:=at(device.pos)
		draw_circle(p,10,Color("b58a22"))
		words(p+Vector2(-35,-17),"反復音",Color("805308"),18)
	for smoke: Dictionary in game.smokes:
		draw_circle(at(smoke.pos),54,Color(0.53,0.67,0.76,0.23))
	for guard: Dictionary in game.guards:
		if guard.hp<=0: continue
		var p:=at(guard.pos)
		var target:=at(guard.target)
		var color:=Color("ca4b17") if guard.id!="C" else Color("5d737d")
		if p.distance_to(target)>12:
			# Dashed direct assignment indicator; not a navigation/path prediction.
			draw_dashed_line(p,target,Color(color,0.45),2,8)
			draw_circle(target,5,color,false,2)
		draw_circle(p,16,Color.WHITE)
		draw_circle(p,13,color)
		words(p+Vector2(-8,7),guard.id,Color.WHITE,20)
		var label_p:=p+Vector2(-65,-23)
		label_p.x=clampf(label_p.x,24,760)
		words(label_p,guard.id+"："+str(game.ROLE_NAMES.get(guard.role,guard.role)),color,18)
		if guard.fire>0.15:
			draw_line(p,at(game.player_pos),Color("df3045"),3)
	var player_at:=at(game.player_pos)
	draw_colored_polygon(PackedVector2Array([player_at+Vector2(0,-17),player_at+Vector2(-15,14),player_at+Vector2(15,14)]),Color("087ac3"))
	words(Vector2(clampf(player_at.x-30,25,850),player_at.y+32),"あなた",Color("0063a2"),20)
	words(Vector2(24,514),"破線＝コードが割り当てた行き先（移動経路そのものではありません）",Color("334c5c"),17)
