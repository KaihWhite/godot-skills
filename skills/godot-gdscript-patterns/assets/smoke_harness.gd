class_name SmokeHarness
extends Node
## Base class for smoke scenes. Subclasses override _tests() and return
## [[label, Callable], ...]. Callables may await. Exits 0 on PASS, 1 on FAIL.

var _name := "smoke"
var _current_test_failed := false


func _ready() -> void:
	_name = get_script().resource_path.get_file().get_basename()
	_say("[%s] starting" % _name)
	var ok := true
	for entry in _tests():
		var passed: bool = await _safe_run(entry[0], entry[1])
		ok = passed and ok
	_say("[%s] result=%s" % [_name, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


func _tests() -> Array:
	return []


func _safe_run(label: String, fn: Callable) -> bool:
	_current_test_failed = false
	await fn.call()
	if _current_test_failed:
		_say("[%s] %s FAIL" % [_name, label])
		return false
	_say("[%s] %s OK" % [_name, label])
	return true


func _check(cond: bool, msg: String) -> bool:
	if cond:
		return true
	_current_test_failed = true
	_say("[%s]   CHECK FAILED: %s" % [_name, msg])
	return false


func _check_near(actual: float, expected: float, tolerance: float, msg: String) -> bool:
	return _check(absf(actual - expected) <= tolerance, "%s: expected %.4f ± %.4f, got %.4f" % [msg, expected, tolerance, actual])


func _say(s: String) -> void:
	print(s)
