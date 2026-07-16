extends SceneTree
# 후반 서지 실측 — "실패가 판 후반에 몰리는가"를 봇 플레이로 계측 (surge_enabled A/B).
# 서지의 목적은 난이도 총량이 아니라 '실패 시점'을 판 후반 30%로 미는 것 —
#   아까운 실패 = F2P 광고 부활의 유인(C47). 그래서 승률보다 '실패 진행도 분포'가 핵심.
# 실행: godot --headless --path . --script tools/surge_probe.gd  (헤드리스 OK — 로직만)
#
# 측정(패배한 판만):
#  - 실패 진행도: 죽은 시점 spawned/total 평균 (서지가 이걸 뒤로 밀어야 함)
#  - 후반 실패%: surge_at 이후에 죽은 패배 비율 (서지가 이걸 올려야 함)
#  - 평균 누수: 거점이 받은 총 누수 (전진 가속이 누수를 늘리는지)

const TRIALS: int = 300

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.dda_enabled = false
	print("── 후반 서지 실측: 실패 시점 분포 (surge A/B) ──")
	for pass_i in range(2):
		g.surge_enabled = (pass_i == 1)
		print("")
		print("[ surge %s ]" % ("ON (after)" if g.surge_enabled else "OFF (before)"))
		print("stage | 승률   | 클리어율 | 평균누수 | 실패진행도 | 후반실패% | 패배(거점/막힘)")
		print("------+--------+----------+----------+-----------+-----------+----------------")
		for si in range(g.STAGES.size()):
			_run_stage(g, si)
	quit()

func _run_stage(g: Node, si: int) -> void:
	var wins: int = 0
	var leak_sum: int = 0
	var places_sum: int = 0
	var clears_sum: int = 0
	var dead_core: int = 0
	var dead_stuck: int = 0
	var fail_prog_sum: float = 0.0   # 패배 판의 spawned/total 합
	var fail_count: int = 0
	var late_fail: int = 0           # surge_at 이후에 죽은 패배 수
	var surge_at: float = float(g.STAGES[si].get("surge_at", 0.0))
	var total: int = int(g.STAGES[si]["total"])

	for t in range(TRIALS):
		var r: Dictionary = _play(g, si)
		places_sum += r["places"]
		clears_sum += r["clears"]
		leak_sum += r["leaked"]
		if r["win"]:
			wins += 1
		else:
			fail_count += 1
			var prog: float = float(r["spawned"]) / float(maxi(1, total))
			fail_prog_sum += prog
			if prog >= surge_at:
				late_fail += 1
			if r["dead_core"]:
				dead_core += 1
			if r["dead_stuck"]:
				dead_stuck += 1

	var n: float = float(TRIALS)
	var fc: float = maxf(1.0, float(fail_count))
	var clear_rate: float = 0.0 if places_sum == 0 else 100.0 * float(clears_sum) / float(places_sum)
	print("  %d   | %5.1f%% |  %4.1f%%   |   %4.2f   |   %5.1f%%   |   %5.1f%%   |  %3d / %3d" % [
		si + 1,
		100.0 * float(wins) / n,
		clear_rate,
		float(leak_sum) / n,
		100.0 * fail_prog_sum / fc,         # 평균 실패 진행도
		100.0 * float(late_fail) / fc,      # 후반(surge_at 이후) 실패 비율
		dead_core, dead_stuck,
	])

func _play(g: Node, si: int) -> Dictionary:
	g._start_stage(si)
	var places: int = 0
	var clears: int = 0
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
		var before: int = g.combo
		g._place_piece()
		places += 1
		if g.resolving or g.combo > before:
			clears += 1
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return {
		"win": g.game_clear, "leaked": g.leaked, "spawned": g.spawned,
		"places": places, "clears": clears,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

# ───────── 그리디 봇 (tools/sim.gd에서 복제) ─────────
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
