extends SceneTree
# 허브 우상단 리더보드 버튼 히트테스트 검증 — 그리기(dy 적용)와 입력(dy 미적용)이 어긋나는지.
#   godot --path . --script tools/ux_hit_probe.gd
var g: Node = null

func _initialize() -> void:
	_run.call_deferred()

func _click(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g.call("_input", ev)
	# 버튼은 **뗄 때** 발동한다(C144) — 누름만 보내면 걸리기만 하고 아무 일도 안 일어난다.
	ev.pressed = false
	g.call("_input", ev)
	await process_frame

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	# 이 프로브의 대상(허브 트로피)이 꺼져 있으면 검사할 게 없다 — 실패가 아니라 해당 없음.
	#   LEADERBOARD_ENABLED를 다시 켜면 아래 dy 어긋남 검사가 자동으로 되살아난다.
	if not bool(g.get("LEADERBOARD_ENABLED")):
		print("SKIP — LEADERBOARD_ENABLED=false (허브 트로피 미노출, 히트테스트 대상 없음)")
		quit()
		return
	for h in [1000, 1280, 1733]:
		DisplayServer.window_set_size(Vector2i(800, h))
		await process_frame
		await process_frame
		g.set("mode", "menu")
		var dy: float = g.call("_ui_dy")
		var lb: Rect2 = g.get("MENU_LB_BTN")
		var drawn: Vector2 = lb.get_center() + Vector2(0.0, dy)   # 화면에 실제로 보이는 위치
		await _click(drawn)
		var hit_drawn: bool = g.get("mode") == "leaderboard"
		g.set("mode", "menu")
		await _click(lb.get_center())                              # dy 없는 논리 위치(=화면 위쪽 빈 곳)
		var hit_logical: bool = g.get("mode") == "leaderboard"
		g.set("mode", "menu")
		print("h=%d dy=%.0f | 보이는곳 클릭→%s | 빈곳(논리좌표) 클릭→%s" % [h, dy, str(hit_drawn), str(hit_logical)])
	quit()
