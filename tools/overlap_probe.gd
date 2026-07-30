extends SceneTree
# 겹침 금지 불변식 탐침 — "한 칸에 유닛 하나"가 실제 플레이에서 깨지는지 본다(0이어야 정상).
#   같이 재는 것: ①겹침 위반 수 ②웨이브 회계 불변식(spawned==killed+leaked+onboard, [[wave-accounting-invariant]])
#   ③slip(옆으로 돌아감)·block(삼면 막힘 대기) 빈도 — block이 잦으면 전진 레버가 눌린다는 뜻(경보).
#   표본은 배치 직전(플레이어가 보는 보드) + 배치 직후 둘 다.
#   실행: TRIALS=6 godot --headless --path . --script tools/overlap_probe.gd

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 6
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	seed(20260718)
	g.seed_game(20260718)
	print("(seed=20260718 TRIALS=%d)" % TRIALS)
	print("idx | 표본   | 겹침위반 | 회계위반 | slip | block")
	print("----+--------+----------+----------+------+------")
	var tot: Dictionary = {"s": 0, "o": 0, "acc": 0, "slip": 0, "blk": 0}
	for si in range(g.STAGES.size()):
		var acc: Dictionary = {"s": 0, "o": 0, "acc": 0, "slip": 0, "blk": 0}
		for t in range(TRIALS):
			_play(g, si, acc)
		print(" %2d | %6d | %8d | %8d | %4d | %5d" % [
			si + 1, acc["s"], acc["o"], acc["acc"], acc["slip"], acc["blk"]])
		for k in acc.keys():
			tot[k] = int(tot[k]) + int(acc[k])
	print("---- 합: 표본 %d | 겹침위반 %d | 회계위반 %d | slip %d | block %d" % [
		tot["s"], tot["o"], tot["acc"], tot["slip"], tot["blk"]])
	print("VERDICT: %s" % ("PASS (겹침 0 · 회계 0)" if int(tot["o"]) == 0 and int(tot["acc"]) == 0 else "FAIL"))
	quit()

func _sample(g: Node, acc: Dictionary) -> void:
	acc["s"] = int(acc["s"]) + 1
	var cnt: Dictionary = {}
	for e in g.enemies:
		var k: int = int(e["row"]) * 100 + int(e["col"])
		cnt[k] = int(cnt.get(k, 0)) + 1
	for k in cnt.keys():
		if int(cnt[k]) >= 2:
			acc["o"] = int(acc["o"]) + (int(cnt[k]) - 1)
	# 웨이브 회계: 적 제거 경로가 보존돼야 한다(gen1 쌍둥이·gem은 카운터 밖 → onboard서 제외)
	var onboard: int = 0
	for e in g.enemies:
		if String(e["etype"]) == "gem":
			continue
		if String(e["etype"]) == "split" and int(e.get("gen", 0)) == 1:
			continue
		onboard += 1
	if int(g.spawned) != int(g.killed) + int(g.leaked) + onboard:
		acc["acc"] = int(acc["acc"]) + 1

func _play(g: Node, si: int, acc: Dictionary) -> void:
	g.dda_enabled = false
	g._start_stage(si)
	g.dbg_slip = 0
	g.dbg_block = 0
	var guard: int = 0
	while not g.game_over and not g.game_clear and guard < 3000:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			s += 1
		if g.game_over or g.game_clear:
			break
		_sample(g, acc)   # 배치 직전(=플레이어가 보는 보드) 상태
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		g._place_piece()
		var s3: int = 0
		while g.resolving and s3 < 400:
			g._process(0.05)
			s3 += 1
		_sample(g, acc)   # 배치 직후(전진·스폰·분열·넉백이 다 적용된 상태)
	acc["slip"] = int(acc["slip"]) + int(g.dbg_slip)
	acc["blk"] = int(acc["blk"]) + int(g.dbg_block)

# ── 그리디 봇 (campaign_probe에서 복사) ──
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
				if String(e.get("etype", "")) == "bomb":
					var fuse: int = int(e.get("fuse", 99))
					score += 250.0 * float(maxi(1, 9 - mini(fuse, 8)))
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
