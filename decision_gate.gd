extends RefCounted

## Simulation-time response gate used by comparison probes.
##
## A scheduled request is removed before its delivery callback runs.  This
## makes callbacks safe to re-enter the gate and makes late HTTP responses
## harmless: once an id is removed, receive() can no longer match it.

var _entries: Dictionary = {}
var _next_id: int = 0


func schedule(due: float, deliver: Callable, cancel: Callable) -> int:
	_next_id += 1
	_entries[_next_id] = {
		"due": due,
		"deliver": deliver,
		"cancel": cancel,
		"received": false,
		"args": [],
	}
	return _next_id


func receive(id: int, args: Array) -> bool:
	if not _entries.has(id):
		return false
	var entry: Dictionary = _entries[id]
	if bool(entry.get("received", false)):
		return false
	entry["received"] = true
	# Capture the response at ingress.  The caller may reuse or mutate its
	# temporary Array before the simulation reaches the deadline.
	entry["args"] = args.duplicate(true)
	_entries[id] = entry
	return true


func tick(now: float) -> void:
	# Snapshot keys so callbacks can schedule/clear entries without changing
	# this traversal.  A callback-created entry waits for the next tick.
	var ids: Array = _entries.keys()
	for id_variant in ids:
		var id: int = int(id_variant)
		if not _entries.has(id):
			continue
		var entry: Dictionary = _entries[id]
		if float(entry["due"]) > now:
			continue
		# Remove before calling user code.  Normal delivery owns request cleanup,
		# so cancel is intentionally not called on this path.
		_entries.erase(id)
		var delivery_args: Array
		if bool(entry.get("received", false)):
			delivery_args = entry["args"]
		else:
			delivery_args = [
				HTTPRequest.RESULT_TIMEOUT,
				0,
				PackedStringArray(),
				PackedByteArray(),
			]
		var deliver: Callable = entry["deliver"]
		if deliver.is_valid():
			deliver.callv(delivery_args)


func clear() -> void:
	# Erase first: cancellation callbacks can safely schedule fresh requests,
	# and those new entries are not part of this cancellation batch.
	var entries: Array = _entries.values()
	_entries.clear()
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		var cancel: Callable = entry["cancel"]
		if cancel.is_valid():
			cancel.call()
