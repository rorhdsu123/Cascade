extends SceneTree
# 결과 팝업 입력 검증 — 힌트 글자를 지운 뒤에도 SPACE·ESC·클릭이 그대로 사는지.
# 버튼 Rect도 옮겼으니(패널 축소) 새 좌표로 클릭이 먹는지 함께 본다.
# 실행: godot --path . --script tools/result_input.gd

func _init() -> void:
	var S: GDScript = load("res://Main.gd")

	# ① 재도전 버튼 클릭 → 같은 스테이지 재시작
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(0)
	g.set_process(false)
	g.killed = 5
	g.leaked = 2
	g.game_over = true
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = g.RETRY_BTN.get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	g._input(click)
	print("재도전 클릭 %s → game_over=%s killed=%d  (재시작이면 false/0)"
			% [g.RETRY_BTN.get_center(), g.game_over, g.killed])

	# ② SPACE → 재도전 (힌트 글자는 지웠지만 키는 살아 있어야)
	var g2: Node = S.new()
	root.add_child(g2)
	await process_frame
	g2._start_stage(0)
	g2.set_process(false)
	g2.killed = 5
	g2.game_over = true
	var sp: InputEventKey = InputEventKey.new()
	sp.keycode = KEY_SPACE
	sp.pressed = true
	g2._input(sp)
	print("SPACE      → game_over=%s killed=%d  (재시작이면 false/0)" % [g2.game_over, g2.killed])

	# ③ ESC → 홈
	var g3: Node = S.new()
	root.add_child(g3)
	await process_frame
	g3._start_stage(0)
	g3.set_process(false)
	g3.game_over = true
	var esc: InputEventKey = InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	g3._input(esc)
	print("ESC        → mode=%s  (홈이면 select)" % g3.mode)

	# ④ 홈 버튼 클릭 → 홈
	var g4: Node = S.new()
	root.add_child(g4)
	await process_frame
	g4._start_stage(0)
	g4.set_process(false)
	g4.game_over = true
	var hc: InputEventMouseButton = InputEventMouseButton.new()
	hc.position = g4.HOME_BTN.get_center()
	hc.button_index = MOUSE_BUTTON_LEFT
	hc.pressed = true
	g4._input(hc)
	print("홈 클릭 %s → mode=%s  (홈이면 select)" % [g4.HOME_BTN.get_center(), g4.mode])

	# ⑤ 빈 곳 클릭 → 아무 일도 없어야(모달)
	var g5: Node = S.new()
	root.add_child(g5)
	await process_frame
	g5._start_stage(0)
	g5.set_process(false)
	g5.game_over = true
	var stray: InputEventMouseButton = InputEventMouseButton.new()
	stray.position = Vector2(60, 950)
	stray.button_index = MOUSE_BUTTON_LEFT
	stray.pressed = true
	g5._input(stray)
	print("빈 곳 클릭 → mode=%s game_over=%s  (그대로 play/true여야)" % [g5.mode, g5.game_over])

	print("DONE")
	quit()
