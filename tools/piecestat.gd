extends SceneTree

# 조각 분포 계측 (일회성) — 그리디 봇으로 실제 플레이하며 '실제로 손에 들어온 조각'을 집계.
# Block Blast 실측치와 비교하기 위함.

const TRIALS: int = 60

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)

	var count: Dictionary = {}
	var cells_sum: float = 0.0
	var n: float = 0.0
	var f_hist: Array = [0, 0, 0, 0, 0]   # f<0.3, <0.45, <0.6, <0.75, >=0.75
	var tier: Dictionary = {"SMALL": 0, "MID": 0, "BIG": 0}

	for si in range(g.STAGES.size()):
		for t in range(TRIALS):
			g._start_stage(si)
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
				# 이 배치 시점의 보드 여유
				var free: int = 0
				for br in range(g.ROWS):
					for bc in range(g.COLS):
						if g.board[br][bc] == "":
							free += 1
				var f: float = float(free) / float(g.ROWS * g.COLS)
				var bi: int = 0
				if f >= 0.75: bi = 4
				elif f >= 0.6: bi = 3
				elif f >= 0.45: bi = 2
				elif f >= 0.3: bi = 1
				f_hist[bi] += 1

				var ty: String = g.tray[mv["slot"]]["type"]
				count[ty] = int(count.get(ty, 0)) + 1
				cells_sum += float((g.PIECES[ty] as Array).size())
				n += 1.0
				if g.SMALL_POOL.has(ty): tier["SMALL"] += 1
				elif g.MID_POOL.has(ty): tier["MID"] += 1
				else: tier["BIG"] += 1

				g.sel = mv["slot"]
				g.hover_col = mv["col"]
				g.hover_row = mv["row"]
				g._place_piece()

	print("\n===== 실제 플레이 중 조각 분포 (%d판, 조각 %d개) =====" % [TRIALS * g.STAGES.size(), int(n)])
	var keys: Array = count.keys()
	keys.sort_custom(func(a, b): return int(count[a]) > int(count[b]))
	for k in keys:
		var pct: float = 100.0 * float(count[k]) / n
		print("  %-4s (%d칸) : %5.2f%%  %s" % [k, (g.PIECES[k] as Array).size(), pct, "#".repeat(int(pct))])
	print("\n티어별:  SMALL %5.2f%%   MID %5.2f%%   BIG(3x3) %5.2f%%" % [
		100.0 * float(tier["SMALL"]) / n, 100.0 * float(tier["MID"]) / n, 100.0 * float(tier["BIG"]) / n])
	print("평균 조각 크기: %.2f칸" % (cells_sum / n))
	var fh: float = 0.0
	for v in f_hist:
		fh += float(v)
	print("배치 시점 보드 여유 f 분포:  <0.30 %4.1f%% | <0.45 %4.1f%% | <0.60 %4.1f%% | <0.75 %4.1f%% | >=0.75 %4.1f%%" % [
		100.0 * float(f_hist[0]) / fh, 100.0 * float(f_hist[1]) / fh, 100.0 * float(f_hist[2]) / fh,
		100.0 * float(f_hist[3]) / fh, 100.0 * float(f_hist[4]) / fh])
	quit()

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
