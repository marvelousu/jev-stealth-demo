extends SceneTree

const Tactics = preload("res://tactics.gd")

const ACTIONS := ["inspect", "paired_inspection", "hold_position", "sweep_last_known", "contain_exits", "flank_and_cover", "counter_watch"]
const NOISE_LOCATION := Vector2(-10, 5)
const DECISION_LOCATION := Vector2(8, -3)

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func reset_game(game) -> void:
	game.replay.stop()
	game._reset()
	game.mode = "rules"
	game.active = false
	await process_frame

func setup_decision_state(game, add_alternate: bool = false) -> Dictionary:
	game.mode = "rules"
	game.power_on = true
	game.time = 10.0
	var observer: Dictionary = game.guards[0]
	if add_alternate:
		Tactics.observe(game, observer, "gunfire", Vector2(-10, 5), "Observed alternate gunfire")
		game.time = 10.0
	return observer

func assignment_by_id(plan: Dictionary, id: String) -> Dictionary:
	for assignment: Dictionary in plan.assignments:
		if assignment.id == id:
			return assignment
	return {}

func guard_by_id(game, id: String) -> Dictionary:
	for guard: Dictionary in game.guards:
		if guard.id == id:
			return guard
	return {}

func path_seconds(game, guard: Dictionary) -> float:
	var points: PackedVector2Array = game.nav.get_point_path(game._nearest_open(game._cell(guard.pos)), game._nearest_open(game._cell(guard.target)))
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length / Tactics.guard_speed(guard.role)

func ids_of(guards: Array) -> Array[String]:
	var ids: Array[String] = []
	for guard: Dictionary in guards:
		ids.append(guard.id)
	ids.sort()
	return ids

func guard_snapshot(game) -> Array:
	var result: Array = []
	for guard: Dictionary in game.guards:
		result.append({
			"id": guard.id,
			"role": guard.role,
			"target": guard.target,
			"pos": guard.pos,
			"events": guard.events.duplicate(true),
			"partner": guard.get("partner", ""),
			"node_position": guard.node.position
		})
	return result

func snapshots_equal(game, before: Array) -> bool:
	if before.size() != game.guards.size():
		return false
	for i in range(game.guards.size()):
		var old: Dictionary = before[i]
		var current: Dictionary = game.guards[i]
		if old.id != current.id or old.role != current.role or old.partner != current.get("partner", ""):
			return false
		if old.target.distance_to(current.target) > 0.001 or old.pos.distance_to(current.pos) > 0.001:
			return false
		if old.node_position.distance_to(current.node.position) > 0.001:
			return false
		if JSON.stringify(old.events) != JSON.stringify(current.events):
			return false
	return true

func plan_for(forecasts: Array, action: String) -> Dictionary:
	for plan: Dictionary in forecasts:
		if plan.action == action:
			return plan
	return {}

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)

	# Forecasting is speculative: none of the source game state may be touched.
	await reset_game(game)
	var observer: Dictionary = setup_decision_state(game, true)
	var before_guards: Array = guard_snapshot(game)
	var before_trace: Array = game.trace.duplicate(true)
	var before_last_plan: String = game.last_plan
	var before_markers: int = game.plan_nodes.size()
	var forecast_actions := ["inspect", "paired_inspection", "hold_position", "counter_watch"]
	for action: String in forecast_actions:
		Tactics.forecast(game, observer, DECISION_LOCATION, [action])
		check(snapshots_equal(game, before_guards) and JSON.stringify(game.trace) == JSON.stringify(before_trace) and game.last_plan == before_last_plan and game.plan_nodes.size() == before_markers, "forecast %s leaves source guards, trace, plan, and markers unchanged" % action)

	# Every forecast assignment matches applying the same action to the same initial state.
	for action: String in ACTIONS:
		await reset_game(game)
		observer = setup_decision_state(game, action == "counter_watch")
		var forecasts: Array = Tactics.forecast(game, observer, DECISION_LOCATION, [action])
		var forecast_plan: Dictionary = plan_for(forecasts, action)
		var forecast_ids: Array[String] = []
		for assignment: Dictionary in forecast_plan.assignments:
			forecast_ids.append(assignment.id)
		forecast_ids.sort()
		var actual_team: Array = Tactics.team(game, observer)
		Tactics.apply(game, action, observer, DECISION_LOCATION)
		var actual_ids: Array[String] = ids_of(actual_team)
		var assignment_match := forecast_ids == actual_ids
		for assignment: Dictionary in forecast_plan.assignments:
			var actual_guard: Dictionary = guard_by_id(game, assignment.id)
			if actual_guard.is_empty() or actual_guard.role != assignment.role or actual_guard.target.distance_to(assignment.target) > 0.001:
				assignment_match = false
			if actual_guard.is_empty() or absf(path_seconds(game, actual_guard) - float(assignment.seconds)) > 0.001:
				assignment_match = false
		check(assignment_match, "forecast assignment matches Tactics.apply for %s including travel timing" % action)

	# Hidden player position is not an input to forecasts or factual observations.
	await reset_game(game)
	observer = setup_decision_state(game, true)
	var hidden_forecasts: Array = Tactics.forecast(game, observer, DECISION_LOCATION, ACTIONS)
	var hidden_observations: Array = Tactics.observations(game, observer, "noise", NOISE_LOCATION, hidden_forecasts)
	game.player_pos = Vector2(12345, 67890)
	var changed_forecasts: Array = Tactics.forecast(game, observer, DECISION_LOCATION, ACTIONS)
	var changed_observations: Array = Tactics.observations(game, observer, "noise", NOISE_LOCATION, changed_forecasts)
	check(JSON.stringify(hidden_forecasts) == JSON.stringify(changed_forecasts) and JSON.stringify(hidden_observations) == JSON.stringify(changed_observations), "hidden player position cannot change forecasts or observations")

	# With the relay off, forecasts include exactly the radio-reachable team used by apply.
	for action: String in ACTIONS:
		await reset_game(game)
		game.power_on = false
		observer = setup_decision_state(game, action == "counter_watch")
		var reachable_before: Array = Tactics.team(game, observer)
		var power_forecast: Dictionary = plan_for(Tactics.forecast(game, observer, DECISION_LOCATION, [action]), action)
		var power_ids: Array[String] = []
		for assignment: Dictionary in power_forecast.assignments:
			power_ids.append(assignment.id)
		power_ids.sort()
		Tactics.apply(game, action, observer, DECISION_LOCATION)
		var reachable_after: Array = ids_of(Tactics.team(game, observer))
		check(power_ids == ids_of(reachable_before) and power_ids == reachable_after, "power-off forecast team matches apply team for %s" % action)

	# Forecast facts fit the observation payload and preserve cross-area history.
	await reset_game(game)
	observer = setup_decision_state(game)
	Tactics.observe(game, observer, "gunfire", Vector2(-10, 5), "Cross-area gunfire from the west")
	game.time = 11.0
	Tactics.observe(game, observer, "gunfire", Vector2(10, 5), "Repeated gunfire from the east")
	game.time = 12.0
	var payload_forecasts: Array = Tactics.forecast(game, observer, DECISION_LOCATION, ["inspect", "paired_inspection"])
	var payload: Array = Tactics.observations(game, observer, "noise", NOISE_LOCATION, payload_forecasts)
	var payload_ids: Dictionary = {}
	var payload_valid := payload.size() <= 12
	for fact: Dictionary in payload:
		var fact_id: String = str(fact.get("id", ""))
		var fact_text: String = str(fact.get("fact", ""))
		if payload_ids.has(fact_id) or fact_text.length() > 240:
			payload_valid = false
		payload_ids[fact_id] = true
	var payload_text := JSON.stringify(payload)
	check(payload_valid and "Cross-area gunfire from the west" in payload_text and "Repeated gunfire from the east" in payload_text, "forecast payload is bounded, has unique IDs, and keeps cross-area repeat history")

	# The first meaningful west noise pulls B west under a pair plan while inspect retains B east.
	await reset_game(game)
	observer = setup_decision_state(game)
	var noise_forecasts: Array = Tactics.forecast(game, observer, NOISE_LOCATION, ["inspect", "paired_inspection"])
	var pair_plan: Dictionary = plan_for(noise_forecasts, "paired_inspection")
	var inspect_plan: Dictionary = plan_for(noise_forecasts, "inspect")
	var pair_b: Dictionary = assignment_by_id(pair_plan, "B")
	var inspect_b: Dictionary = assignment_by_id(inspect_plan, "B")
	check(pair_b.role == "support" and pair_b.target.x < 0 and pair_plan.west == 2 and pair_plan.east == 0 and inspect_b.role == "patrol" and inspect_b.target.x > 0 and inspect_plan.west == 1 and inspect_plan.east == 1, "first west noise pair pulls B west while inspect retains B on the east")

	# Forecast and live guard movement share the same role speed table.
	await reset_game(game)
	var expected_speeds := {"patrol": 1.9, "investigate": 3.8, "support": 3.8, "block": 3.8, "flank": 3.8, "search": 3.8, "pursue": 3.8, "down": 1.9, "wait_cover": 3.8, "watch": 1.9, "ambush": 3.8, "sentry": 1.9}
	var speeds_match := true
	for role: String in expected_speeds:
		if not is_equal_approx(Tactics.guard_speed(role), float(expected_speeds[role])):
			speeds_match = false
	check(speeds_match, "all guard roles use the shared Tactics.guard_speed table")

	print("FORECAST_VERIFICATION %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		print("FORECAST_FAILURE ", failure)
	game.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
