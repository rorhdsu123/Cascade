extends SceneTree

# 밸런스 튜너 (일회성) — 스테이지별 파라미터 후보를 한 번에 A/B.
# DDA ON, 120판. sim.gd보다 빠르게 방향만 잡는 용도.

const TRIALS: int = 120

# 스테이지별 후보: {} = 현재값 그대로(기준선)
# 1차 결과: step_every는 절벽(스5 2.5%) → 못 씀. spawn_every는 비단조(스3에서 오히려 쉬워짐) → 안 씀.
# core_hp(허용 누수) + total(적 수)만 손잡이로 쓴다. 목표 승률: 스2 79 / 스3 65 / 스4 46 / 스5 31.
# 스3은 1차에서 {core_hp:3, total:34} = 63.3%로 이미 목표 도달 → 2차 탐색에서 제외.
const CANDIDATES: Dictionary = {
	1: [
		{"core_hp": 4, "total": 32},
		{"core_hp": 4, "total": 34},
		{"core_hp": 3, "total": 30},
	],
	3: [
		{"core_hp": 2, "total": 40},
		{"core_hp": 2, "total": 44},
		{"core_hp": 2, "total": 48},
	],
	4: [
		{"core_hp": 2, "total": 48},
		{"core_hp": 2, "total": 54},
		{"core_hp": 1, "total": 44},
	],
}

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.dda_enabled = true

	print("\n stage | 후보                                        | 승률   | 누수 | 거점사 | 막힘사")
	print("-------+---------------------------------------------+--------+------+--------+-------")
	for si in CANDIDATES.keys():
		for cand in CANDIDATES[si]:
			# const STAGES는 읽기 전용 → 원본을 복제해 덮어쓴 st를 주입한다
			var patched: Dictionary = (g.STAGES[si] as Dictionary).duplicate(true)
			for k in cand.keys():
				patched[k] = cand[k]
			var wins: int = 0
			var leak: float = 0.0
			var dc: int = 0
			var ds: int = 0
			for t in range(TRIALS):
				var r: Dictionary = _play(g, si, patched)
				if r["win"]:
					wins += 1
				leak += float(r["leaked"])
				if r["dead_core"]:
					dc += 1
				if r["dead_stuck"]:
					ds += 1
			print("   %d   | %-43s | %5.1f%% | %4.2f |  %3d   |  %3d" % [
				si + 1, str(cand) if not cand.is_empty() else "(현재값)",
				100.0 * float(wins) / float(TRIALS), leak / float(TRIALS), dc, ds])
		print("-------+---------------------------------------------+--------+------+--------+-------")
	quit()

func _play(g: Node, si: int, patched: Dictionary) -> Dictionary:
	g.stage_idx = si
	g.st = patched
	g.mode = "play"
	g._init_game()
	var guard: int = 0
	while not g.game_over and not g.game_clear and guard < 3000:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			s += 1
		if g.game_over or g.game_clear:
			break
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		g._place_piece()
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return {
		"win": g.game_clear, "leaked": g.leaked,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

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
		var fc: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]:
				fc = false
				break
		if fc:
			full_cols.append(c)
	var lines: int = full_rows.size() + full_cols.size()
	var score: float = 500.0 * float(lines)
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
