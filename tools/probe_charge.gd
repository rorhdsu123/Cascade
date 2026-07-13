extends SceneTree

# 줄 폭발 타임라인 검증 — 충전 홀드(콤보 비례) → 순차 파괴 → 로켓/라벨.
# 계약: ① 홀드가 콤보에 비례해 길어진다
#       ② 배치 직후에도 완성 줄은 board에 남아 있다
#       ③ 셀이 전부 "동시에" 사라진다 (BB 실측: 1프레임)
#       ④ COMBO 라벨(flash)은 마지막 셀이 부서진 뒤에 뜬다 — 파괴와 안 겹침
#       ⑤ 로켓은 파괴가 끝난 뒤에 나간다

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)

	print("① 콤보별 충전 홀드")
	for cb in [1, 2, 3, 4, 5, 6, 8]:
		print("   콤보 %d → %.2fs" % [cb, g._charge_dur_for(cb)])
	print("   (Block Blast 실측: 콤보2 ≈0.27s, 콤보4 ≈0.55s)")
	print()

	_run(g, 3)

func _run(g: Node, combo: int) -> void:
	g._start_stage(0)
	for r in range(g.ROWS):
		for c in range(g.COLS):
			g.board[r][c] = ""
	for c in range(g.COLS - 1):
		g.board[4][c] = "B"
	g.tray[0] = {"key": "1", "offsets": [Vector2i(0, 0)], "color": "Y"}
	g.sel = 0
	g.hover_col = 7
	g.hover_row = 4
	g.combo = combo - 1   # _place_piece가 +1 → 목표 콤보

	g._place_piece()
	print("콤보 %d 로 폭발 — 충전 홀드 %.2fs, 총 길이 %.2fs" % [g.combo, g.charge_dur, g.resolve_total])

	var alive0: int = 0
	for c in range(g.COLS):
		if g.board[4][c] != "":
			alive0 += 1
	print("② 배치 직후 줄 생존 %d/8 (기대 8)" % alive0)

	print("③ 시간에 따른 줄 잔여 셀 (8 → 0 으로 한 번에 떨어져야 함)")
	var flash_at: float = -1.0
	var rocket_at: float = -1.0
	var last_pop_at: float = -1.0
	var prev: int = 8
	var steps: int = 0
	while g.resolving and steps < 2000:
		g._process(0.01)
		steps += 1
		if g.hitstop > 0.0:
			continue
		var left: int = 0
		var shape: String = ""
		for c in range(g.COLS):
			if g.board[4][c] != "":
				left += 1
				shape += "■"
			else:
				shape += "·"
		if left != prev:
			print("   t=%.2f  %s  (%d칸)" % [g.resolve_timer, shape, left])
			prev = left
			if left == 0:
				last_pop_at = g.resolve_timer
		if flash_at < 0.0 and g.flash_timer > 0.0:
			flash_at = g.resolve_timer
		if rocket_at < 0.0 and g.rockets.size() > 0:
			rocket_at = g.resolve_timer
	print("④ COMBO 라벨 t=%.2f — 마지막 셀 파괴(t=%.2f) 뒤인가? %s"
			% [flash_at, last_pop_at, flash_at >= last_pop_at])
	print("⑤ 첫 로켓 t=%.2f — 파괴 끝난 뒤인가? %s" % [rocket_at, rocket_at >= last_pop_at])
	quit()
