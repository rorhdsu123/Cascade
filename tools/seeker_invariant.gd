extends SceneTree
# 웨이브 회계 불변식 탐침 — 씨커(비행기) 처치 경로가 spawned==killed+leaked+onboard를 깨는지.
#   [[wave-accounting-invariant]]: 부활이 이걸 깨서 소프트락(C89). 처치 경로 변경 후 필수 검증.
# gen0(원본)만 카운터에 셈 — 쌍둥이(split gen1)는 순수 추가라 onboard에서 뺀다.
# 실행: godot --headless --script tools/seeker_invariant.gd

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _onboard_gen0(g: Node) -> int:
	var n: int = 0
	for e in g.enemies:
		if String(e["etype"]) == "gem":
			continue
		if String(e["etype"]) == "split" and int(e.get("gen", 0)) == 1:
			continue   # 쌍둥이는 카운터 밖
		n += 1
	return n

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var violations: int = 0
	var stages_tested: int = 0
	for si in [0, 1, 2, 4, 6, 7]:   # basic·swarm·blitz·armor·split·last
		main.call("_start_stage", si)
		stages_tested += 1
		var guard: int = 0
		while not main.game_over and not main.game_clear and guard < 2000:
			guard += 1
			var s: int = 0
			while main.resolving and s < 400:
				main.call("_process", 0.05)
				s += 1
			# 불변식 체크(resolve 소화 후, 다음 배치 전)
			var sp: int = main.spawned
			var kl: int = main.killed
			var lk: int = main.leaked
			var ob: int = _onboard_gen0(main)
			if sp != kl + lk + ob:
				violations += 1
				if violations <= 8:
					print("❌ s", si, " g", guard, ": spawned ", sp, " != killed ", kl, " + leaked ", lk, " + onboard ", ob, " (=", kl+lk+ob, ")")
			if main.game_over or main.game_clear:
				break
			var mv: Dictionary = _best_move(main)
			if mv.is_empty():
				break
			main.sel = mv["slot"]
			main.hover_col = mv["col"]
			main.hover_row = mv["row"]
			main.call("_place_piece")
		var s2: int = 0
		while main.resolving and s2 < 400:
			main.call("_process", 0.05)
			s2 += 1
	print("── 불변식: 스테이지 ", stages_tested, "개 · 위반 ", violations, "건 ──")
	print("DONE")
	quit()

# ── 봇 헬퍼(regress.gd에서 복사) ──
func _best_move(g: Node) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1e9
	for slot in range(3):
		if g.tray[slot].is_empty():
			continue
		var offsets: Array = g.tray[slot]["offsets"]
		for r in range(g.ROWS):
			for c in range(g.COLS):
				var cells: Array = []
				var ok: bool = true
				for o in offsets:
					var ov: Vector2i = o as Vector2i
					var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
					if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS:
						ok = false
						break
					if g.board[cc.y][cc.x] != "":
						ok = false
						break
					cells.append(cc)
				if not ok:
					continue
				var sc: float = _score(g, cells, slot)
				if sc > best_score:
					best_score = sc
					best = {"slot": slot, "col": c, "row": r}
	return best

func _score(g: Node, cells: Array, slot: int) -> float:
	var occ: Array = []
	for r in range(g.ROWS):
		var row: Array = []
		for c in range(g.COLS):
			row.append(g.board[r][c] != "")
		occ.append(row)
	for ci in cells:
		var cv: Vector2i = ci as Vector2i
		occ[cv.y][cv.x] = true

	var full_rows: Array = []
	var full_cols: Array = []
	for r in range(g.ROWS):
		var fr: bool = true
		for c in range(g.COLS):
			if not occ[r][c]:
				fr = false
				break
		if fr:
			full_rows.append(r)
	for c in range(g.COLS):
		var fcx: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]:
				fcx = false
				break
		if fcx:
			full_cols.append(c)

	var lines: int = full_rows.size() + full_cols.size()
	var score: float = 0.0
	score += 500.0 * float(lines)

	var after: Array = []
	for r2 in range(g.ROWS):
		var row2: Array = []
		for c2 in range(g.COLS):
			var f: bool = occ[r2][c2]
			if full_rows.has(r2) or full_cols.has(c2):
				f = false
			row2.append(f)
		after.append(row2)
	var others: int = 0
	for slot2 in range(3):
		if slot2 == slot or g.tray[slot2].is_empty():
			continue
		others += 1
		if not _fits_anywhere(g, after, g.tray[slot2]["offsets"]):
			score -= 900.0
	if others == 0:
		var free: int = 0
		for r3 in range(g.ROWS):
			for c3 in range(g.COLS):
				if not after[r3][c3]:
					free += 1
		if free < 12:
			score -= 300.0

	if lines > 0:
		var lanes: int = maxi(1, g.combo + 1)
		var hit: int = 0
		for e in g.enemies:
			var in_band: bool = false
			for fc2 in full_cols:
				if absi(int(e["col"]) - int(fc2)) < lanes:
					in_band = true
			for fr2 in full_rows:
				if absi(int(e["row"]) - int(fr2)) < lanes:
					in_band = true
			if in_band:
				hit += 1
		score += 120.0 * float(hit)
		for e in g.enemies:
			for fc3 in full_cols:
				if int(e["col"]) == int(fc3):
					score += 8.0 * float(e["row"])

	var filled: int = 0
	var holes: int = 0
	for r in range(g.ROWS):
		for c in range(g.COLS):
			if occ[r][c]:
				filled += 1
			else:
				var nb: int = 0
				if r == 0 or occ[r - 1][c]:
					nb += 1
				if r == g.ROWS - 1 or occ[r + 1][c]:
					nb += 1
				if c == 0 or occ[r][c - 1]:
					nb += 1
				if c == g.COLS - 1 or occ[r][c + 1]:
					nb += 1
				if nb == 4:
					holes += 1
	var fill_frac: float = float(filled) / float(g.ROWS * g.COLS)
	score -= 60.0 * fill_frac * fill_frac * float(g.ROWS * g.COLS) / 10.0
	score -= 70.0 * float(holes)

	var touch: int = 0
	for ci2 in cells:
		var cv2: Vector2i = ci2 as Vector2i
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cv2.x + d.x
			var ny: int = cv2.y + d.y
			if nx < 0 or nx >= g.COLS or ny < 0 or ny >= g.ROWS:
				touch += 1
			elif g.board[ny][nx] != "":
				touch += 1
	score += 4.0 * float(touch)
	return score

func _fits_anywhere(g: Node, occ: Array, offsets: Array) -> bool:
	for r in range(g.ROWS):
		for c in range(g.COLS):
			var ok: bool = true
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				var x: int = c + ov.x
				var y: int = r + ov.y
				if x < 0 or x >= g.COLS or y < 0 or y >= g.ROWS or occ[y][x]:
					ok = false
					break
			if ok:
				return true
	return false
