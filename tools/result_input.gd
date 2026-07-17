extends SceneTree
# 결과 팝업 입력 검증 — 광고 부활(C47) 반영. 버튼 좌표는 _result_layout()가 단일 출처.
#   부활 가능(거점 파괴 실패 & 미사용)이면 [광고 이어하기]가 주·[재도전]이 부, 아니면 [재도전]이 주.
# 실행: godot --headless --path . --script tools/result_input.gd  (로직·입력만 — 렌더 없음)

func _init() -> void:
	var S: GDScript = load("res://Main.gd")

	# ── A. 부활 가능(거점 파괴·미사용): 광고 버튼 클릭 → 세컨드 윈드
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(0)
	g.set_process(false)
	g.killed = 8
	g.combo = 4
	# 상단 적(row 2, 유지) + 하단 3줄 적(row 6, 제거). ROWS=8이라 row>=5가 하단 3줄.
	g.enemies = [
		{"col": 2, "row": 2, "vis_row": 2.0, "hp": 10, "maxhp": 10, "etype": "basic", "id": 1, "step_every": 3},
		{"col": 5, "row": 6, "vis_row": 6.0, "hp": 10, "maxhp": 10, "etype": "basic", "id": 2, "step_every": 3},
	]
	g.game_over = true
	g.stuck = false
	var lay: Dictionary = g._result_layout()
	print("[A] 부활가능? %s  (거점파괴·미사용 → true 여야)" % lay["revivable"])
	var cc: InputEventMouseButton = InputEventMouseButton.new()
	cc.position = (lay["cont"] as Rect2).get_center()
	cc.button_index = MOUSE_BUTTON_LEFT
	cc.pressed = true
	g._input(cc)
	var top_left: int = 0
	for e in g.enemies:
		if int(e["row"]) < g.ROWS - g.REVIVE_CLEAR_ROWS:
			top_left += 1
	print("    광고클릭 → game_over=%s · core_hp=%d(복구=%d) · 적=%d(상단유지=%d) · combo=%d · revive_used=%s"
			% [g.game_over, g.core_hp, int(g.st["core_hp"]), g.enemies.size(), top_left, g.combo, g.revive_used])
	print("        (하단3줄 적만 제거 → 적=1/상단유지=1, combo=0)")

	# ── B. 거점 부활 후 '막힘'으로 재사망: 원인이 달라도 판당 1회 → 이어하기 안 뜸
	g.game_over = true
	g.stuck = true          # 첫 부활은 거점 파괴였고, 이번엔 막힘으로 죽음
	g.killed = 12
	var lay2: Dictionary = g._result_layout()
	print("[B] 거점부활 후 '막힘' 재사망 부활가능? %s  (원인 무관 판당 1회 → false 여야)" % lay2["revivable"])
	var sp: InputEventKey = InputEventKey.new()
	sp.keycode = KEY_SPACE
	sp.pressed = true
	g._input(sp)
	print("    SPACE → game_over=%s killed=%d  (재시작이면 false/0)" % [g.game_over, g.killed])

	# ── C. 막힘(stuck) 실패: 부활 가능 — 광고 클릭 시 보드를 비운다(세컨드 윈드)
	var gc: Node = S.new()
	root.add_child(gc)
	await process_frame
	gc._start_stage(0)
	gc.set_process(false)
	gc.game_over = true
	gc.stuck = true
	# 보드를 꽉 채워 막힘 상황 재현 + 적 2마리(부활 후에도 남아야)
	for r in range(gc.ROWS):
		for c in range(gc.COLS):
			gc.board[r][c] = "R"
	gc.enemies = [
		{"col": 1, "row": 2, "vis_row": 2.0, "hp": 5, "maxhp": 5, "etype": "basic", "id": 3, "step_every": 3},
		{"col": 4, "row": 5, "vis_row": 5.0, "hp": 5, "maxhp": 5, "etype": "basic", "id": 4, "step_every": 3},
	]
	var layc: Dictionary = gc._result_layout()
	print("[C] 막힘 부활가능? %s  (→ true 여야)" % layc["revivable"])
	var ccc: InputEventMouseButton = InputEventMouseButton.new()
	ccc.position = (layc["cont"] as Rect2).get_center()
	ccc.button_index = MOUSE_BUTTON_LEFT
	ccc.pressed = true
	gc._input(ccc)
	var filled: int = 0
	var bottom_filled: int = 0
	for r in range(gc.ROWS):
		for c in range(gc.COLS):
			if gc.board[r][c] != "":
				filled += 1
				if r >= gc.ROWS - gc.REVIVE_CLEAR_ROWS:
					bottom_filled += 1
	# 부분 클리어: 하단 3줄(24칸)만 비고 상단 40칸 유지 + 적은 그대로(막힘은 적 유지) = '이어하는' 느낌
	print("    광고클릭 → game_over=%s stuck=%s 보드채움=%d 하단3줄채움=%d 적=%d  (false/false/40/0/적2 유지)"
			% [gc.game_over, gc.stuck, filled, bottom_filled, gc.enemies.size()])

	# ── D. 부활 가능 시 SPACE → 부활(주 동작이 이어하기)
	var gd: Node = S.new()
	root.add_child(gd)
	await process_frame
	gd._start_stage(0)
	gd.set_process(false)
	gd.game_over = true
	gd.enemies = [{"col": 1, "row": 2, "vis_row": 2.0, "hp": 5, "maxhp": 5, "etype": "basic", "id": 2, "step_every": 3}]
	var spd: InputEventKey = InputEventKey.new()
	spd.keycode = KEY_SPACE
	spd.pressed = true
	gd._input(spd)
	print("[D] SPACE(부활가능) → game_over=%s revive_used=%s 적=%d  (부활이면 false/true/0)"
			% [gd.game_over, gd.revive_used, gd.enemies.size()])

	# ── E. 홈 버튼 클릭 → 홈 / 빈 곳 클릭 → 무시(모달)
	var ge: Node = S.new()
	root.add_child(ge)
	await process_frame
	ge._start_stage(0)
	ge.set_process(false)
	ge.game_over = true
	var le: Dictionary = ge._result_layout()
	var hc: InputEventMouseButton = InputEventMouseButton.new()
	hc.position = (le["home"] as Rect2).get_center()
	hc.button_index = MOUSE_BUTTON_LEFT
	hc.pressed = true
	ge._input(hc)
	print("[E] 홈클릭 → mode=%s  (홈이면 select)" % ge.mode)

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
	print("    빈곳클릭 → mode=%s game_over=%s  (그대로 play/true여야)" % [g5.mode, g5.game_over])

	print("DONE")
	quit()
