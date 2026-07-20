extends SceneTree
# 터치→마우스 에뮬레이션 end-to-end 검증. [[godot-pixel-verify-needs-window]] 창 필수.
#   godot --path . --script tools/touch_probe.gd
# InputEventScreenTouch/Drag를 Input.parse_input_event로 흘려, emulate_mouse_from_touch가
# 마우스 이벤트를 합성해 기존 _input(집기/드래그/놓기)이 반응하는지 확인. 반응하면 ScreenDrag 재작성 불필요.

func _initialize() -> void:
	_run.call_deferred()

func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)
	await process_frame
	await process_frame

func _drag(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)
	await process_frame
	await process_frame

func _filled(g: Node) -> int:
	var b: Array = g.get("board")
	var n: int = 0
	for r in b:
		for c in r:
			if c != "":
				n += 1
	return n

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(800, 1400))
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	# 스테이지0 플레이 진입
	g.call("_start_stage", 0)
	await process_frame
	await process_frame
	print("mode=%s dragging=%s click_mode=%s filled_before=%d" % [
		g.get("mode"), g.get("dragging"), g.get("click_mode"), _filled(g)])

	# 트레이 슬롯0의 조각을 터치로 집어 → 보드 중앙으로 드래그 → 뗀다
	var slot0: Rect2 = g.call("_tray_slot_rect", 0)
	var start: Vector2 = slot0.get_center()
	var target: Vector2 = g.call("_cell_center", 3, 4)   # 보드 (col3,row4)
	await _touch(start, true)
	print("after touch-press: dragging=%s drag_slot=%s" % [g.get("dragging"), g.get("drag_slot")])
	await _drag(target, target - start)
	print("after drag: hover_col=%s hover_row=%s dragging=%s" % [
		g.get("hover_col"), g.get("hover_row"), g.get("dragging")])
	await _touch(target, false)
	var placed: bool = _filled(g) > 0
	print("after touch-release: filled_after=%d PLACED=%s" % [_filled(g), placed])
	print("TOUCH_EMULATION_OK=%s" % str(placed))
	quit()
