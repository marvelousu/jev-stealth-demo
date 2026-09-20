extends RefCounted
## Ordinary mission rules. Observation replay is explicitly a separate mode.
const PICKUP_TIME := 1.2
const EXTRACT_TIME := 2.5
const DAMAGE := 34.0
const AIM_TIME := 0.65

static func reset(game) -> void:
	game.ammo=6
	game.interaction_progress=0.0
	game.interaction_kind=""
	game.last_damage_at=-100.0
	game.damage_flash=0.0
	game.damage_taken=0.0
	game.first_damage_at=-1.0
	game.lethal_damage_at=-1.0
	game.detected_count=0
	game.success=false
	game.noise_charges=3
	game.smoke_charges=2
	game.interaction_origin=game.player_pos

static func observation_mode(game) -> bool:
	return game.replay.comparing or game.replay.playing

static func speed(game, crouching: bool) -> float:
	return (2.2 if crouching else 3.2) if game.has_case else (2.7 if crouching else 4.2)

static func hurt(game, amount: float, shooter: String="") -> void:
	game.damage_taken+=amount
	if game.first_damage_at<0: game.first_damage_at=game.time
	if game.damage_taken>=100 and game.lethal_damage_at<0: game.lethal_damage_at=game.time
	game.damage_flash=0.35
	game.last_damage_at=game.time
	game.interaction_progress=0
	if not observation_mode(game) or not game.replay.invulnerable: game.player_hp=maxf(0,game.player_hp-amount)
	game.feedback.record(game,"hit",("敵" if shooter.is_empty() else shooter)+"から被弾（耐久%d）"%int(game.player_hp),{"guard":shooter,"damage":amount})

static func tick(game, delta: float) -> void:
	game.damage_flash=maxf(0,game.damage_flash-delta)
	if game.player_hp<=0:
		game._finish(false)
		return
	if observation_mode(game) and not game.replay.allows_objective_interactions:
		game.interaction_kind=""
		game.interaction_progress=0
		return
	var kind: String=""
	if not game.has_case and game.player_pos.distance_to(game.CASE_POS)<1.65 and game._clear_line(game.player_pos,game.CASE_POS,false): kind="pickup"
	if game.has_case:
		for exit_pos: Vector2 in game.EXITS:
			if game.player_pos.distance_to(exit_pos)<1.25: kind="extract"
	if kind!=game.interaction_kind:
		game.interaction_progress=0
		game.interaction_origin=game.player_pos
	game.interaction_kind=kind
	if kind.is_empty() or not Input.is_action_pressed("interact") or game.time-game.last_damage_at<0.6:
		game.interaction_progress=0
		game.interaction_origin=game.player_pos
		return
	if game.player_pos.distance_to(game.interaction_origin)>0.2:
		game.interaction_progress=0
		game.interaction_origin=game.player_pos
	game.interaction_progress+=delta
	if kind=="pickup" and game.interaction_progress>=PICKUP_TIME:
		game.has_case=true
		game.feedback.record(game,"pickup","ケースを確保・携行で減速")
		game.level.case_visual.hide()
		game._sfx("pickup")
		game._log("ケース確保：運搬中は減速。南の出口でEを2.5秒長押し")
		game.interaction_progress=0
		game.interaction_kind=""
	elif kind=="extract" and game.interaction_progress>=EXTRACT_TIME:
		game._finish(true)

static func aim_lines(game) -> void:
	# Aim warning appears only when this guard can actually see the player.
	for guard: Dictionary in game.guards:
		if guard.hp>0 and guard.fire>0.08 and game._sees(guard,game.player_pos,8.0):
			game._beam(game._v3(guard.pos,0.9),game._v3(game.player_pos,0.65),Color(1.0,0.22,0.18,0.45))
